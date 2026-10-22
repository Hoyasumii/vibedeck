//! Operações com o `Store`: edição de workflows e ciclo de vida das execuções.
//!
//! Porta de `ProjectStore.swift` (seções Workflows e Workflow runs), `AIWorkflowRunner.swift` (parte Core:
//! checkpoint e retomada) e `saveRunOutput` de `AICatalog.swift`. Agentes, comandos e skills são lidos pelo
//! `Store` genérico, sem depender do módulo `resources`.

use std::fs;
use std::path::PathBuf;

use super::WorkflowQuestionDraft;
use super::engine::{self, RunAction};
use super::error::{Result, WorkflowError, invalid};
use super::ext::{provider_str, status_str};
use super::plan::{WorkflowPlan, skill_resources_suffix};
use super::prompts;
use crate::error::Error;
use crate::model::*;
use crate::slug;
use crate::store::{Record, RunRecord, Store, write_atomic};

// ---- workflows ---------------------------------------------------------------------------------------

pub fn list_workflows(store: &Store) -> Result<Vec<Record<Workflow>>> {
    Ok(store.workflows()?)
}

/// Resolve slug, id/prefixo ou título para o slug do workflow.
pub fn resolve_workflow_slug(store: &Store, reference: &str) -> Result<String> {
    Ok(store.resolve::<Workflow>(reference)?)
}

pub fn load_workflow(store: &Store, slug: &str) -> Result<Workflow> {
    Ok(store.load::<Workflow>(slug)?)
}

pub fn create_workflow(
    store: &Store,
    title: &str,
    summary: Option<String>,
    input: Option<String>,
    max_steps: Option<i64>,
    tags: Vec<String>,
    author: Author,
) -> Result<Record<Workflow>> {
    let title = title.trim();
    if title.is_empty() {
        return Err(Error::InvalidName.into());
    }
    let mut wf = Workflow::new(title);
    wf.summary = summary;
    wf.input = input;
    wf.max_steps = max_steps;
    wf.tags = tags;
    wf.author = author;
    Ok(store.create(&wf, None)?)
}

/// Aplica `change` ao workflow e grava (com `updatedAt` novo). Erro em `change` não grava nada.
pub fn update_workflow(
    store: &Store,
    reference: &str,
    change: impl FnOnce(&mut Workflow) -> Result<()>,
) -> Result<Record<Workflow>> {
    let slug = resolve_workflow_slug(store, reference)?;
    let mut wf = load_workflow(store, &slug)?;
    change(&mut wf)?;
    wf.updated_at = Timestamp::now();
    store.save_workflow(&slug, &wf)?;
    Ok(Record { slug, value: wf })
}

pub fn delete_workflow(store: &Store, slug: &str) -> Result<()> {
    Ok(store.delete_workflow(slug)?)
}

fn step_index(wf: &Workflow, step: &str) -> Result<usize> {
    wf.step_index(step)
        .ok_or_else(|| invalid(format!("etapa não encontrada: {step}.")))
}

/// Slug de um agente, comando ou skill existente (slug, id/prefixo ou título).
fn resolve_step_target(store: &Store, kind: NextStepKind, target: &str) -> Result<String> {
    Ok(match kind {
        NextStepKind::Agent => store.resolve::<Agent>(target)?,
        NextStepKind::Command => store.resolve::<Command>(target)?,
        NextStepKind::Skill => store.resolve::<Skill>(target)?,
    })
}

/// Acrescenta uma etapa que roda um agente/comando/skill existente (o mesmo pode aparecer mais de uma vez).
/// Devolve o workflow e o id (único no workflow) da nova etapa.
pub fn add_workflow_step(
    store: &Store,
    reference: &str,
    kind: NextStepKind,
    target: &str,
    note: Option<&str>,
) -> Result<(Record<Workflow>, String)> {
    let stored = resolve_step_target(store, kind, target)?;
    let mut id = String::new();
    let rec = update_workflow(store, reference, |wf| {
        id = wf.new_step_id(&stored);
        let mut step = WorkflowStep::new(id.clone(), kind, stored.clone());
        step.note = note
            .map(str::trim)
            .filter(|n| !n.is_empty())
            .map(str::to_string);
        wf.steps.push(step);
        Ok(())
    })?;
    Ok((rec, id))
}

/// Remove uma etapa (id ou posição) e as transições que apontam para ela.
pub fn remove_workflow_step(
    store: &Store,
    reference: &str,
    step: &str,
) -> Result<Record<Workflow>> {
    update_workflow(store, reference, |wf| {
        let i = step_index(wf, step)?;
        wf.remove_step(i);
        Ok(())
    })
}

/// Move uma etapa para a posição (1-based; 1 = início).
pub fn move_workflow_step(
    store: &Store,
    reference: &str,
    step: &str,
    position: i64,
) -> Result<Record<Workflow>> {
    update_workflow(store, reference, |wf| {
        let from = step_index(wf, step)?;
        let moved = wf.steps.remove(from);
        let at = (position - 1).max(0).min(wf.steps.len() as i64) as usize;
        wf.steps.insert(at, moved);
        Ok(())
    })
}

/// Acrescenta a transição `from` → `to`. `verdict` casa a última linha do resultado da etapa; `when` é uma
/// condição em linguagem natural; sem nenhum é o "senão" (um por etapa, sempre por último).
pub fn add_workflow_transition(
    store: &Store,
    reference: &str,
    from: &str,
    to: &str,
    when: Option<&str>,
    verdict: Option<&str>,
) -> Result<Record<Workflow>> {
    let clean = |s: Option<&str>| {
        s.map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
    };
    update_workflow(store, reference, |wf| {
        let source = step_index(wf, from)?;
        let target = wf.steps[step_index(wf, to)?].id.clone();
        let transition = WorkflowTransition::new(clean(verdict), clean(when), target.clone());
        if transition.is_fallback()
            && wf.steps[source]
                .transitions
                .iter()
                .any(|t| t.is_fallback() && t.to != target)
        {
            return Err(invalid(format!(
                "a etapa {} já tem uma transição sem condição (senão).",
                wf.steps[source].id
            )));
        }
        wf.add_transition(transition, source);
        Ok(())
    })
}

/// Define (ou limpa, com `None`/valor <= 0) o máximo de execuções da etapa por ciclo.
pub fn set_workflow_step_max_visits(
    store: &Store,
    reference: &str,
    step: &str,
    max_visits: Option<i64>,
) -> Result<Record<Workflow>> {
    update_workflow(store, reference, |wf| {
        let i = step_index(wf, step)?;
        wf.steps[i].max_visits = max_visits.filter(|n| *n > 0);
        Ok(())
    })
}

/// Remove a transição de posição `index` (1-based) de uma etapa.
pub fn remove_workflow_transition(
    store: &Store,
    reference: &str,
    from: &str,
    index: i64,
) -> Result<Record<Workflow>> {
    update_workflow(store, reference, |wf| {
        let source = step_index(wf, from)?;
        let len = wf.steps[source].transitions.len() as i64;
        if index < 1 || index > len {
            return Err(invalid(format!(
                "a etapa {} não tem a transição {index}.",
                wf.steps[source].id
            )));
        }
        wf.steps[source].transitions.remove(index as usize - 1);
        Ok(())
    })
}

/// JSON que orquestra a IA através do workflow.
pub fn workflow_plan(store: &Store, reference: &str, input: Option<&str>) -> Result<WorkflowPlan> {
    let slug = resolve_workflow_slug(store, reference)?;
    let wf = load_workflow(store, &slug)?;
    Ok(WorkflowPlan::build(
        &slug,
        &wf,
        input,
        &store.agents()?,
        &store.commands()?,
        &store.skills()?,
    ))
}

// ---- execuções (runs) --------------------------------------------------------------------------------

/// `<workflow>/<execução>` → `(workflow, execução)`; sem as duas partes devolve `("", ref)`.
pub fn split_run_ref(reference: &str) -> (String, String) {
    match reference.split_once('/') {
        Some((w, r)) if !w.is_empty() && !r.is_empty() => (w.to_string(), r.to_string()),
        _ => (String::new(), reference.to_string()),
    }
}

/// Pasta da execução (guarda `run.json` e o que as etapas escrevem).
pub fn run_dir(store: &Store, workflow: &str, run: &str) -> PathBuf {
    store.runs_dir().join(workflow).join(run)
}

fn run_file_exists(store: &Store, reference: &str) -> bool {
    let (w, r) = split_run_ref(reference);
    !w.is_empty() && run_dir(store, &w, &r).join("run.json").is_file()
}

/// Toda execução, mais recente primeiro; `workflow` filtra por workflow (referência resolvida).
pub fn list_runs(store: &Store, workflow: Option<&str>) -> Result<Vec<RunRecord>> {
    if !store.runs_dir().is_dir() {
        return Ok(vec![]);
    }
    let wanted = match workflow {
        Some(w) => Some(resolve_workflow_slug(store, w)?),
        None => None,
    };
    let all = store.runs()?;
    Ok(match wanted {
        Some(slug) => all
            .into_iter()
            .filter(|r| split_run_ref(&r.reference).0 == slug)
            .collect(),
        None => all,
    })
}

/// Resolve `<workflow>/<execução>`, o nome de uma execução único entre workflows, ou o id (prefixo >= 4).
pub fn resolve_run_ref(store: &Store, reference: &str) -> Result<String> {
    let reference = reference.trim();
    let runs = list_runs(store, None)?;
    if let Some(exact) = runs.iter().find(|r| r.reference == reference) {
        return Ok(exact.reference.clone());
    }
    let needle = reference.to_lowercase();
    let matches: Vec<&RunRecord> = runs
        .iter()
        .filter(|r| {
            let id = r.run.id.to_string().to_lowercase();
            r.reference.rsplit('/').next() == Some(reference)
                || id == needle
                || (needle.chars().count() >= 4 && id.starts_with(&needle))
        })
        .collect();
    match matches.as_slice() {
        [] => Err(Error::RunNotFound(reference.to_string()).into()),
        [one] => Ok(one.reference.clone()),
        _ => Err(invalid(format!(
            "execução ambígua: {reference}; use <workflow>/<execução>."
        ))),
    }
}

pub fn load_run(store: &Store, reference: &str) -> Result<WorkflowRun> {
    let (w, r) = split_run_ref(reference);
    if w.is_empty() {
        return Err(Error::RunNotFound(reference.to_string()).into());
    }
    Ok(store.load_run(&w, &r)?)
}

pub fn save_run(store: &Store, run: &WorkflowRun, reference: &str) -> Result<()> {
    let (w, r) = split_run_ref(reference);
    if w.is_empty() {
        return Err(Error::RunNotFound(reference.to_string()).into());
    }
    store.save_run(&w, &r, run)?;
    Ok(())
}

/// Título e modelo (por provedor) e prompt de uma etapa, lidos do agente/comando/skill. Tudo `None` se faltar.
fn resolved_step(
    store: &Store,
    step: &WorkflowStep,
    provider: AiProvider,
) -> (Option<String>, Option<String>, Option<String>) {
    fn model_for(
        settings: &Option<ProviderSettingsMap>,
        provider: AiProvider,
        model: &Option<String>,
    ) -> Option<String> {
        settings
            .as_ref()
            .and_then(|m| m.get(provider_str(provider)))
            .and_then(|s| s.model.clone())
            .or_else(|| model.clone())
    }
    match step.kind {
        NextStepKind::Agent => store
            .load::<Agent>(&step.r#ref)
            .ok()
            .map(|a| {
                (
                    Some(a.title.clone()),
                    model_for(&a.provider_settings, provider, &a.model),
                    Some(a.prompt),
                )
            })
            .unwrap_or_default(),
        NextStepKind::Command => store
            .load::<Command>(&step.r#ref)
            .ok()
            .map(|c| {
                (
                    Some(c.title.clone()),
                    model_for(&c.provider_settings, provider, &c.model),
                    Some(c.prompt),
                )
            })
            .unwrap_or_default(),
        NextStepKind::Skill => store
            .load::<Skill>(&step.r#ref)
            .ok()
            .map(|s| {
                let suffix = skill_resources_suffix(&s);
                (
                    Some(s.title.clone()),
                    model_for(&s.provider_settings, provider, &s.model),
                    Some(format!("{}{suffix}", s.prompt)),
                )
            })
            .unwrap_or_default(),
    }
}

fn action_for(store: &Store, run: &WorkflowRun, reference: &str, wf: &Workflow) -> RunAction {
    engine::next(run, reference, wf, |step| {
        let (title, model, _) = resolved_step(store, step, run.provider);
        (title, model)
    })
}

/// Inicia uma execução. O nome é o da entrada, então iniciar de novo com a mesma entrada a retoma: uma em
/// andamento fica onde está; uma terminada abre novo ciclo (de `from` ou do início).
pub fn start_run(
    store: &Store,
    workflow_ref: &str,
    input: Option<&str>,
    from: Option<&str>,
    provider: Option<AiProvider>,
) -> Result<(String, WorkflowRun, RunAction)> {
    let wf_slug = resolve_workflow_slug(store, workflow_ref)?;
    let wf = load_workflow(store, &wf_slug)?;
    if wf.steps.is_empty() {
        return Err(invalid("o workflow não tem etapas."));
    }
    let input = input.map(str::trim).filter(|s| !s.is_empty());
    let name = match input {
        Some(i) => slug::make(i),
        None => {
            let stamp = crate::time::now().format("%Y-%m-%dT%H:%M:%S").to_string();
            slug::unique(
                &format!("execucao-{}", slug::make(&stamp)),
                &store.runs_dir().join(&wf_slug),
                "",
            )
        }
    };
    let reference = format!("{wf_slug}/{name}");
    let mut run;
    if run_file_exists(store, &reference) {
        run = load_run(store, &reference)?;
        engine::restart(&mut run, &wf, from)?;
    } else {
        run = WorkflowRun::new(
            wf_slug.clone(),
            input.map(str::to_string),
            wf.steps.first().map(|s| s.id.clone()),
            provider.unwrap_or(AiProvider::Claude),
        );
        if from.is_some() {
            engine::restart(&mut run, &wf, from)?;
        }
    }
    save_run(store, &run, &reference)?;
    let action = action_for(store, &run, &reference, &wf);
    Ok((reference, run, action))
}

/// O que o orquestrador faz agora.
pub fn next_run_action(store: &Store, reference: &str) -> Result<RunAction> {
    let reference = resolve_run_ref(store, reference)?;
    let run = load_run(store, &reference)?;
    let wf = load_workflow(store, &run.workflow)?;
    Ok(action_for(store, &run, &reference, &wf))
}

/// Registra o veredito da etapa atual e devolve a próxima ação (`decide` quando há condições a julgar).
pub fn record_run(
    store: &Store,
    reference: &str,
    verdict: Option<&str>,
    summary: Option<&str>,
    to: Option<&str>,
    none_holds: bool,
) -> Result<RunAction> {
    let reference = resolve_run_ref(store, reference)?;
    let mut run = load_run(store, &reference)?;
    let wf = load_workflow(store, &run.workflow)?;
    if let Some(decide) =
        engine::record(&mut run, &wf, verdict, summary, to, none_holds, &reference)?
    {
        return Ok(decide);
    }
    run.checkpoint = None;
    save_run(store, &run, &reference)?;
    Ok(action_for(store, &run, &reference, &wf))
}

/// Grava perguntas da etapa atual; a execução passa a esperar as respostas.
pub fn ask_run(
    store: &Store,
    reference: &str,
    questions: &[WorkflowQuestionDraft],
) -> Result<Vec<WorkflowQuestion>> {
    let reference = resolve_run_ref(store, reference)?;
    let mut run = load_run(store, &reference)?;
    let added = engine::ask(&mut run, questions)?;
    save_run(store, &run, &reference)?;
    Ok(added)
}

pub fn answer_run(store: &Store, reference: &str, number: i64, answer: &str) -> Result<RunAction> {
    let reference = resolve_run_ref(store, reference)?;
    let mut run = load_run(store, &reference)?;
    engine::answer(&mut run, number, answer)?;
    save_run(store, &run, &reference)?;
    let wf = load_workflow(store, &run.workflow)?;
    Ok(action_for(store, &run, &reference, &wf))
}

pub fn stop_run(store: &Store, reference: &str, reason: Option<&str>) -> Result<WorkflowRun> {
    let reference = resolve_run_ref(store, reference)?;
    let mut run = load_run(store, &reference)?;
    engine::stop(&mut run, reason);
    save_run(store, &run, &reference)?;
    Ok(run)
}

/// Apaga a execução e a pasta dela (inclusive o que as etapas gravaram).
pub fn delete_run(store: &Store, reference: &str) -> Result<()> {
    let reference = resolve_run_ref(store, reference)?;
    let (w, r) = split_run_ref(&reference);
    let dir = run_dir(store, &w, &r);
    fs::remove_dir_all(&dir).map_err(|e| Error::Io {
        path: dir,
        source: e,
    })?;
    Ok(())
}

/// Prompt da etapa atual da execução, para o subagente que a executa.
pub fn run_step_prompt(store: &Store, reference: &str, cli: &str) -> Result<String> {
    let reference = resolve_run_ref(store, reference)?;
    let run = load_run(store, &reference)?;
    let wf = load_workflow(store, &run.workflow)?;
    let step = run
        .current
        .as_ref()
        .filter(|_| !run.is_finished())
        .and_then(|c| wf.steps.iter().find(|s| &s.id == c));
    let Some(step) = step else {
        return Err(invalid(format!(
            "a execução {reference} não tem etapa a rodar ({}).",
            status_str(run.status)
        )));
    };
    let (title, _, instructions) = resolved_step(store, step, run.provider);
    let (w, r) = split_run_ref(&reference);
    Ok(prompts::step_prompt(
        &run,
        &reference,
        &wf,
        step,
        title.as_deref(),
        instructions.as_deref(),
        &run_dir(store, &w, &r),
        cli,
    ))
}

// ---- checkpoint e retomada (parte Core do runner de IA) --------------------------------------------

const INVALID_TRANSITION: &str =
    "A IA retornou uma transição inválida. A execução permanece na etapa atual.";

/// Grava o checkpoint da etapa em andamento (resultado durável que separa concluir a etapa de julgar as
/// transições condicionais).
pub fn checkpoint_run(
    store: &Store,
    reference: &str,
    checkpoint: WorkflowStepCheckpoint,
) -> Result<()> {
    let mut run = load_run(store, reference)?;
    if run.current.as_deref() != Some(checkpoint.step.as_str()) || run.is_finished() {
        return Err(WorkflowError::Plain(INVALID_TRANSITION.into()));
    }
    run.checkpoint = Some(checkpoint);
    run.updated_at = Timestamp::now();
    save_run(store, &run, reference)
}

/// Retomada explícita: mantém etapa atual, histórico, respostas do usuário e contadores das guardas.
pub fn resume_run(store: &Store, reference: &str) -> Result<WorkflowRun> {
    let mut run = load_run(store, reference)?;
    if run.status == WorkflowRunStatus::Stopped && run.current.is_some() {
        run.status = if run.open_questions().is_empty() {
            WorkflowRunStatus::Running
        } else {
            WorkflowRunStatus::Waiting
        };
        run.reason = None;
        run.updated_at = Timestamp::now();
        save_run(store, &run, reference)?;
    }
    Ok(run)
}

/// Saída completa de uma etapa vai para a pasta da execução; o histórico guarda só a referência.
pub fn save_run_output(store: &Store, reference: &str, output: &str) -> Result<String> {
    let reference = resolve_run_ref(store, reference)?;
    let (w, r) = split_run_ref(&reference);
    let file = run_dir(store, &w, &r)
        .join("outputs")
        .join(format!("{}.md", Id::new()));
    write_atomic(&file, output.as_bytes())?;
    let rel = file
        .strip_prefix(store.root())
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| file.to_string_lossy().into_owned());
    Ok(format!(
        "Saída completa em `{rel}` ({} caracteres). Leia quando necessário; não é um resumo do conteúdo.",
        output.chars().count()
    ))
}
