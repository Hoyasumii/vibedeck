//! Plano: JSON que orquestra a IA através do workflow (`workflow_flow`, `workflows flow`).

use std::collections::{BTreeMap, HashSet};

use serde::Serialize;

use crate::model::*;
use crate::store::Record;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPlanStep {
    pub id: String,
    pub kind: NextStepKind,
    pub r#ref: String,
    /// Agente/comando/skill resolvido (ausente quando a referência não existe).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_settings: Option<ProviderSettingsMap>,
    /// Só comandos: o que vai em `$ARGUMENTS`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub argument_hint: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_visits: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transitions: Option<Vec<WorkflowTransition>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warnings: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPlan {
    pub workflow: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    /// O que o workflow pede (`Workflow.input`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input_hint: Option<String>,
    /// A entrada desta execução.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input: Option<String>,
    pub max_steps: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start: Option<String>,
    /// Como executar o workflow (pt-BR), para a IA que o orquestra.
    pub rules: Vec<String>,
    pub steps: Vec<WorkflowPlanStep>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warnings: Option<Vec<String>>,
}

const EXECUTION_RULES: &[&str] = &[
    "Comece pela etapa `start`, usando `input` como entrada. Sem `input`, e com `inputHint`, pergunte ao usuário antes de começar.",
    "Em cada etapa, anuncie \"▶ Etapa <id> — <title>\" e execute o `prompt` dela sobre a entrada e o resultado da etapa anterior: agente = assuma o papel (ou use um subagente com esse prompt e o `model`), comando = troque $ARGUMENTS pela `note` ou pela entrada, skill = siga as instruções. A `note` é uma instrução extra da etapa.",
    "Termine cada etapa com o veredito na última linha. Depois, escolha a transição: primeiro a que tiver `verdict` igual ao veredito (sem diferenciar maiúsculas e acentos), depois a primeira cujo `when` for verdadeiro para o resultado, por fim a sem `verdict` e sem `when` (senão). Voltar para etapas anteriores é permitido.",
    "Se nenhuma transição se aplicar, ou a etapa não tiver transições, o workflow termina.",
    "Nunca execute mais que `maxSteps` etapas no total, nem uma etapa mais vezes que o `maxVisits` dela; se atingir um limite, pare e avise o usuário.",
    "Para execução com estado em disco, uma etapa por subagente e perguntas ao usuário, prefira `vibedeck runs start` (ou `workflow_run_start`) e siga o orquestrador.",
    "Ignore os próximos passos (nextSteps) dos agentes, comandos e skills: só as transições do workflow valem.",
    "Se uma condição depender de uma decisão do usuário, pergunte antes de seguir.",
    "Ao terminar, resuma o caminho percorrido (etapas e transições escolhidas) e o resultado final.",
];

fn trim_non_empty(s: &Option<String>) -> Option<String> {
    s.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Sufixo de recursos de uma skill importada: pasta do `SKILL.md`.
pub(crate) fn skill_resources_suffix(skill: &Skill) -> String {
    skill
        .source_path
        .as_ref()
        .map(|p| {
            let dir = std::path::Path::new(p)
                .parent()
                .map(|d| d.to_string_lossy().into_owned())
                .unwrap_or_default();
            format!("\nRecursos da skill: {dir}")
        })
        .unwrap_or_default()
}

impl WorkflowPlan {
    pub fn build(
        slug: &str,
        workflow: &Workflow,
        input: Option<&str>,
        agents: &[Record<Agent>],
        commands: &[Record<Command>],
        skills: &[Record<Skill>],
    ) -> WorkflowPlan {
        // `uniquingKeysWith: { a, _ in a }`: vale o primeiro de cada slug (`find` já devolve o primeiro).
        let find_agent = |r: &str| agents.iter().find(|x| x.slug == r).map(|x| &x.value);
        let find_command = |r: &str| commands.iter().find(|x| x.slug == r).map(|x| &x.value);
        let find_skill = |r: &str| skills.iter().find(|x| x.slug == r).map(|x| &x.value);
        let ids: HashSet<&str> = workflow.steps.iter().map(|s| s.id.as_str()).collect();
        let steps: Vec<WorkflowPlanStep> = workflow
            .steps
            .iter()
            .map(|step| {
                let mut out = WorkflowPlanStep {
                    id: step.id.clone(),
                    kind: step.kind,
                    r#ref: step.r#ref.clone(),
                    title: None,
                    model: None,
                    provider_settings: None,
                    argument_hint: None,
                    note: trim_non_empty(&step.note),
                    max_visits: step.max_visits,
                    prompt: None,
                    transitions: (!step.transitions.is_empty()).then(|| step.transitions.clone()),
                    warnings: None,
                };
                let mut warnings: Vec<String> = Vec::new();
                match step.kind {
                    NextStepKind::Agent => match find_agent(&step.r#ref) {
                        Some(a) => {
                            out.title = Some(a.title.clone());
                            out.model = a.model.clone();
                            out.prompt = Some(a.prompt.clone());
                            out.provider_settings = a.provider_settings.clone();
                        }
                        None => warnings.push(format!("Agente não encontrado: {}", step.r#ref)),
                    },
                    NextStepKind::Command => match find_command(&step.r#ref) {
                        Some(c) => {
                            out.title = Some(c.title.clone());
                            out.model = c.model.clone();
                            out.argument_hint = c.argument_hint.clone();
                            out.prompt = Some(c.prompt.clone());
                            out.provider_settings = c.provider_settings.clone();
                        }
                        None => warnings.push(format!("Comando não encontrado: {}", step.r#ref)),
                    },
                    NextStepKind::Skill => match find_skill(&step.r#ref) {
                        Some(s) => {
                            out.title = Some(s.title.clone());
                            out.model = s.model.clone();
                            out.prompt = Some(format!("{}{}", s.prompt, skill_resources_suffix(s)));
                            out.provider_settings = s.provider_settings.clone();
                        }
                        None => warnings.push(format!("Skill não encontrada: {}", step.r#ref)),
                    },
                }
                for t in &step.transitions {
                    if !ids.contains(t.to.as_str()) {
                        warnings.push(format!("Transição para etapa inexistente: {}", t.to));
                    }
                }
                out.warnings = (!warnings.is_empty()).then_some(warnings);
                out
            })
            .collect();
        let mut warnings: Vec<String> = Vec::new();
        if workflow.steps.is_empty() {
            warnings.push("O workflow não tem etapas.".into());
        }
        let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
        for s in &workflow.steps {
            *counts.entry(s.id.as_str()).or_default() += 1;
        }
        let duplicated: Vec<&str> = counts
            .into_iter()
            .filter(|(_, n)| *n > 1)
            .map(|(k, _)| k)
            .collect();
        if !duplicated.is_empty() {
            warnings.push(format!("Ids de etapa repetidos: {}", duplicated.join(", ")));
        }
        WorkflowPlan {
            workflow: slug.to_string(),
            title: workflow.title.clone(),
            summary: trim_non_empty(&workflow.summary),
            input_hint: trim_non_empty(&workflow.input),
            input: input
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string),
            max_steps: workflow.max_steps.unwrap_or(DEFAULT_MAX_STEPS).max(1),
            start: workflow.steps.first().map(|s| s.id.clone()),
            rules: EXECUTION_RULES.iter().map(|s| s.to_string()).collect(),
            steps,
            warnings: (!warnings.is_empty()).then_some(warnings),
        }
    }

    /// Todo aviso do plano (do workflow e por etapa), para telas de validação.
    pub fn all_warnings(&self) -> Vec<String> {
        let mut out = self.warnings.clone().unwrap_or_default();
        for step in &self.steps {
            for w in step.warnings.clone().unwrap_or_default() {
                out.push(format!("{}: {w}", step.id));
            }
        }
        out
    }

    /// JSON pretty do plano (sem `\n` final), para colar em um prompt.
    pub fn json(&self) -> Result<String, serde_json::Error> {
        let bytes = crate::json::encode(self)?;
        let mut text = String::from_utf8_lossy(&bytes).into_owned();
        if text.ends_with('\n') {
            text.pop();
        }
        Ok(text)
    }

    /// Mensagem que pede à IA para executar o workflow agora, com o plano em JSON.
    pub fn prompt(&self) -> Result<String, serde_json::Error> {
        Ok(format!(
            "Execute o workflow \"{}\" do VibeDeck seguindo o JSON abaixo (máquina de estados: etapas, transições e regras de execução em `rules`).\n\n```json\n{}\n```",
            self.title,
            self.json()?
        ))
    }
}
