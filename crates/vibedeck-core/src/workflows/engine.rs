//! Máquina de estados pura sobre um `WorkflowRun` (sem disco), como `WorkflowRunEngine` do Swift.
//! As mensagens `reason` em pt-BR fazem parte do dado gravado: copiadas literalmente.

use serde::{Deserialize, Serialize};

use super::WorkflowQuestionDraft;
use super::error::{Result, invalid};
use super::ext::status_str;
use crate::model::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RunActionKind {
    /// Lançar um subagente para `step`.
    #[serde(rename = "run-step")]
    RunStep,
    /// Perguntar ao usuário as perguntas abertas, gravar as respostas e chamar `next`.
    #[serde(rename = "ask")]
    Ask,
    /// Nenhum veredito casou e a etapa tem condições textuais: julgá-las e chamar `record` com `to`.
    #[serde(rename = "decide")]
    Decide,
    /// Terminou normalmente.
    #[serde(rename = "done")]
    Done,
    /// Parada por guarda ou pelo usuário.
    #[serde(rename = "stop")]
    Stop,
}

impl RunActionKind {
    pub fn as_str(self) -> &'static str {
        match self {
            RunActionKind::RunStep => "run-step",
            RunActionKind::Ask => "ask",
            RunActionKind::Decide => "decide",
            RunActionKind::Done => "done",
            RunActionKind::Stop => "stop",
        }
    }
}

/// O que o orquestrador faz a seguir: o motor decide, o chat obedece.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RunAction {
    pub action: RunActionKind,
    /// `<workflow>/<execução>`.
    pub run: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Modelo do agente/comando/skill da etapa (para o subagente).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub reason: String,
    /// Em `decide`: as transições condicionais a julgar (em ordem).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidates: Option<Vec<WorkflowTransition>>,
    /// Em `decide`: o veredito a reenviar com `record`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verdict: Option<String>,
    /// Em `ask`: as perguntas abertas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub questions: Option<Vec<WorkflowQuestion>>,
}

impl RunAction {
    pub fn new(action: RunActionKind, run: &str, reason: impl Into<String>) -> Self {
        RunAction {
            action,
            run: run.to_string(),
            step: None,
            title: None,
            model: None,
            reason: reason.into(),
            candidates: None,
            verdict: None,
            questions: None,
        }
    }
}

fn trim_non_empty(s: &str) -> Option<String> {
    let t = s.trim();
    (!t.is_empty()).then(|| t.to_string())
}

fn open_questions(run: &WorkflowRun) -> Vec<WorkflowQuestion> {
    run.questions
        .iter()
        .filter(|q| q.is_open())
        .cloned()
        .collect()
}

fn step_id(reference: &str, workflow: &Workflow) -> Result<String> {
    match workflow.step_index(reference) {
        Some(i) => Ok(workflow.steps[i].id.clone()),
        None => Err(invalid(format!("etapa não encontrada: {reference}."))),
    }
}

/// Reinício explícito: novo ciclo, mantém o histórico e fecha as perguntas antigas.
pub fn restart_from_beginning(run: &mut WorkflowRun, workflow: &Workflow) -> Result<()> {
    let Some(first) = workflow.steps.first().map(|s| s.id.clone()) else {
        return Err(invalid("o workflow não tem etapas."));
    };
    run.cycle += 1;
    run.current = Some(first);
    run.checkpoint = None;
    run.questions.clear();
    run.status = WorkflowRunStatus::Running;
    run.reason = None;
    run.updated_at = Timestamp::now();
    Ok(())
}

/// Reinicia uma execução terminada (novo ciclo, a partir de `from` ou do início); uma em andamento fica onde está.
pub fn restart(run: &mut WorkflowRun, workflow: &Workflow, from: Option<&str>) -> Result<()> {
    let target = from.map(|f| step_id(f, workflow)).transpose()?;
    if !run.is_finished() && target.is_none() {
        return Ok(());
    }
    let Some(first) = target.or_else(|| workflow.steps.first().map(|s| s.id.clone())) else {
        return Err(invalid("o workflow não tem etapas."));
    };
    if run.is_finished() && !run.history.is_empty() {
        run.cycle += 1;
    }
    run.current = Some(first);
    run.checkpoint = None;
    run.status = if open_questions(run).is_empty() {
        WorkflowRunStatus::Running
    } else {
        WorkflowRunStatus::Waiting
    };
    run.reason = None;
    run.updated_at = Timestamp::now();
    Ok(())
}

/// O que fazer agora. `resolve` devolve `(título, modelo)` da etapa.
pub fn next(
    run: &WorkflowRun,
    reference: &str,
    workflow: &Workflow,
    resolve: impl Fn(&WorkflowStep) -> (Option<String>, Option<String>),
) -> RunAction {
    match run.status {
        WorkflowRunStatus::Done => {
            return RunAction::new(
                RunActionKind::Done,
                reference,
                run.reason
                    .clone()
                    .unwrap_or_else(|| "o workflow terminou".into()),
            );
        }
        WorkflowRunStatus::Stopped => {
            let mut a = RunAction::new(
                RunActionKind::Stop,
                reference,
                run.reason
                    .clone()
                    .unwrap_or_else(|| "execução parada".into()),
            );
            a.step = run.current.clone();
            return a;
        }
        WorkflowRunStatus::Running | WorkflowRunStatus::Waiting => {}
    }
    let open = open_questions(run);
    if let Some(first) = open.first() {
        let step = first.step.clone();
        let mut a = RunAction::new(
            RunActionKind::Ask,
            reference,
            format!("pergunta(s) aberta(s) da etapa {step}"),
        );
        a.step = Some(step);
        a.questions = Some(open);
        return a;
    }
    let step = run
        .current
        .as_ref()
        .and_then(|c| workflow.steps.iter().find(|s| &s.id == c));
    let (Some(current), Some(step)) = (run.current.as_ref(), step) else {
        let mut a = RunAction::new(
            RunActionKind::Stop,
            reference,
            format!(
                "etapa atual inexistente no workflow: {}",
                run.current.as_deref().unwrap_or("nenhuma")
            ),
        );
        a.step = run.current.clone();
        return a;
    };
    let (title, model) = resolve(step);
    let visits = run
        .current_cycle()
        .iter()
        .filter(|e| &e.step == current)
        .count();
    let reason = if visits == 0 {
        format!("próxima etapa: {current}")
    } else {
        format!("etapa {current} de novo ({}ª vez neste ciclo)", visits + 1)
    };
    let mut a = RunAction::new(RunActionKind::RunStep, reference, reason);
    a.step = Some(current.clone());
    a.title = title;
    a.model = model;
    a
}

/// Registra o resultado da etapa atual e avança. Devolve `decide` (sem gravar nada) quando só condições em
/// linguagem natural podem decidir e `to`/`none_holds` não foram dados.
pub fn record(
    run: &mut WorkflowRun,
    workflow: &Workflow,
    verdict: Option<&str>,
    summary: Option<&str>,
    to: Option<&str>,
    none_holds: bool,
    reference: &str,
) -> Result<Option<RunAction>> {
    if run.is_finished() {
        return Err(invalid(format!(
            "a execução já terminou ({}); use start para retomar.",
            status_str(run.status)
        )));
    }
    if !open_questions(run).is_empty() {
        return Err(invalid(
            "há perguntas abertas: responda-as antes de registrar a etapa.",
        ));
    }
    let step = run
        .current
        .as_ref()
        .and_then(|c| workflow.steps.iter().find(|s| &s.id == c));
    let (Some(current), Some(step)) = (run.current.clone(), step) else {
        return Err(invalid(format!(
            "etapa atual inexistente no workflow: {}.",
            run.current.as_deref().unwrap_or("nenhuma")
        )));
    };
    let verdict: Option<String> = verdict.and_then(trim_non_empty);
    let next: Option<String>;
    if let Some(to) = to {
        let target = step_id(to, workflow)?;
        if !step.transitions.iter().any(|t| t.to == target) {
            return Err(invalid(format!(
                "a etapa {current} não tem transição para {target}."
            )));
        }
        next = Some(target);
    } else if let Some(m) = verdict
        .as_deref()
        .and_then(|v| step.transitions.iter().find(|t| t.matches(v)))
    {
        next = Some(m.to.clone());
    } else {
        let conditions: Vec<WorkflowTransition> = step
            .transitions
            .iter()
            .filter(|t| t.verdict.is_none() && t.when.is_some())
            .cloned()
            .collect();
        if !conditions.is_empty() && !none_holds {
            let mut a = RunAction::new(
                RunActionKind::Decide,
                reference,
                "nenhum veredito casou: avalie as condições na ordem e registre com `to` (ou `nenhuma`)",
            );
            a.step = Some(current);
            a.candidates = Some(conditions);
            a.verdict = verdict;
            return Ok(Some(a));
        }
        next = step
            .transitions
            .iter()
            .find(|t| t.is_fallback())
            .map(|t| t.to.clone());
    }

    let previous = run.history.last().cloned();
    let now = Timestamp::now();
    run.history.push(WorkflowRunEntry {
        step: current.clone(),
        verdict: verdict.clone(),
        summary: summary.and_then(trim_non_empty),
        next: next.clone(),
        cycle: run.cycle,
        at: now,
    });
    run.updated_at = now;
    run.current = next.clone();
    let Some(next) = next else {
        run.status = WorkflowRunStatus::Done;
        run.reason = Some(format!(
            "a etapa {current} terminou{} e nenhuma transição se aplica",
            verdict
                .as_ref()
                .map(|v| format!(" com {v}"))
                .unwrap_or_default()
        ));
        return Ok(None);
    };
    let cycle_count = run.current_cycle().len() as i64;
    let max_steps = workflow.max_steps.unwrap_or(DEFAULT_MAX_STEPS).max(1);
    let visits_to_next = run
        .current_cycle()
        .iter()
        .filter(|e| e.step == next)
        .count() as i64;
    let next_limit = workflow
        .steps
        .iter()
        .find(|s| s.id == next)
        .and_then(|s| s.max_visits);
    if cycle_count >= max_steps {
        run.status = WorkflowRunStatus::Stopped;
        run.reason = Some(format!(
            "limite de {max_steps} etapas por execução atingido (maxSteps)"
        ));
    } else if let Some(limit) = next_limit.filter(|l| visits_to_next >= *l) {
        run.status = WorkflowRunStatus::Stopped;
        run.reason = Some(format!(
            "a etapa {next} já rodou {limit} vez(es) neste ciclo (maxVisits): decida se libera mais uma"
        ));
    } else if next == current
        && let Some(prev) = previous
        && prev.cycle == run.cycle
        && prev.step == current
        && prev.verdict.as_deref().map(WorkflowTransition::normalize)
            == verdict.as_deref().map(WorkflowTransition::normalize)
    {
        run.status = WorkflowRunStatus::Stopped;
        run.reason = Some(format!(
            "a etapa {current} voltou para si com o mesmo veredito duas vezes seguidas: não andou"
        ));
    }
    Ok(None)
}

/// Grava perguntas da etapa atual; a execução espera as respostas.
pub fn ask(
    run: &mut WorkflowRun,
    drafts: &[WorkflowQuestionDraft],
) -> Result<Vec<WorkflowQuestion>> {
    let step = match (&run.current, run.is_finished()) {
        (Some(s), false) => s.clone(),
        _ => return Err(invalid("a execução não tem etapa em andamento.")),
    };
    let drafts: Vec<&WorkflowQuestionDraft> = drafts
        .iter()
        .filter(|d| !d.question.trim().is_empty())
        .collect();
    if drafts.is_empty() {
        return Err(invalid("nenhuma pergunta recebida."));
    }
    let now = Timestamp::now();
    let mut number = run.questions.iter().map(|q| q.number).max().unwrap_or(0);
    let added: Vec<WorkflowQuestion> = drafts
        .iter()
        .map(|d| {
            number += 1;
            WorkflowQuestion {
                number,
                step: step.clone(),
                question: d.question.trim().to_string(),
                context: d.context.as_deref().and_then(trim_non_empty),
                options: d
                    .options
                    .clone()
                    .unwrap_or_default()
                    .into_iter()
                    .filter(|o| !o.label.trim().is_empty())
                    .collect(),
                multiple: d.multiple.unwrap_or(false),
                answer: None,
                created_at: now,
                answered_at: None,
            }
        })
        .collect();
    run.questions.extend(added.iter().cloned());
    run.status = WorkflowRunStatus::Waiting;
    run.reason = Some(format!("aguardando resposta do usuário (etapa {step})"));
    run.updated_at = now;
    Ok(added)
}

/// Grava a resposta do usuário; sem perguntas abertas a execução volta a rodar a mesma etapa.
pub fn answer(run: &mut WorkflowRun, number: i64, text: &str) -> Result<()> {
    let Some(i) = run.questions.iter().position(|q| q.number == number) else {
        return Err(invalid(format!("pergunta não encontrada: {number}.")));
    };
    let Some(text) = trim_non_empty(text) else {
        return Err(invalid("resposta vazia."));
    };
    let now = Timestamp::now();
    run.questions[i].answer = Some(text);
    run.questions[i].answered_at = Some(now);
    if open_questions(run).is_empty() && run.status == WorkflowRunStatus::Waiting {
        run.status = WorkflowRunStatus::Running;
        run.reason = None;
    }
    run.updated_at = now;
    Ok(())
}

pub fn stop(run: &mut WorkflowRun, reason: Option<&str>) {
    run.status = WorkflowRunStatus::Stopped;
    run.reason = Some(
        reason
            .and_then(trim_non_empty)
            .unwrap_or_else(|| "parada pelo usuário".into()),
    );
    run.updated_at = Timestamp::now();
}
