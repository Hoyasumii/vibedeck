//! Fluxo (JSON que orquestra a IA): agente/comando/skill + próximos passos resolvidos, com aviso de ciclo.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

use super::error::Result;
use crate::Store;
use crate::json;
use crate::model::*;
use crate::store::Record;

/// Agente, comando ou skill resolvido dentro de um fluxo.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentFlowNode {
    pub kind: NextStepKind,
    /// Slug do agente/comando/skill do VibeDeck.
    pub r#ref: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_settings: Option<ProviderSettingsMap>,
    /// Só comandos: o que vai em `$ARGUMENTS`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub argument_hint: Option<String>,
    pub prompt: String,
    pub next: Vec<AgentFlowStep>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentFlowStep {
    pub kind: NextStepKind,
    pub r#ref: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Item resolvido (ausente em ciclos já expandidos acima ou referências inexistentes).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node: Option<Box<AgentFlowNode>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}

fn key(kind: NextStepKind, r: &str) -> String {
    let k = match kind {
        NextStepKind::Agent => "agent",
        NextStepKind::Command => "command",
        NextStepKind::Skill => "skill",
    };
    format!("{k}:{r}")
}

struct Index<'a> {
    agents: HashMap<&'a str, &'a Agent>,
    commands: HashMap<&'a str, &'a Command>,
    skills: HashMap<&'a str, &'a Skill>,
}

/// Monta o fluxo a partir de `slug` (`AgentFlow.build`). `None` se o slug não existe.
pub fn build(
    kind: NextStepKind,
    slug: &str,
    agents: &[Record<Agent>],
    commands: &[Record<Command>],
    skills: &[Record<Skill>],
) -> Option<AgentFlowNode> {
    // `uniquingKeysWith: { a, _ in a }`: vence o primeiro de cada slug.
    fn index<T>(records: &[Record<T>]) -> HashMap<&str, &T> {
        let mut m = HashMap::new();
        for r in records {
            m.entry(r.slug.as_str()).or_insert(&r.value);
        }
        m
    }
    let idx = Index {
        agents: index(agents),
        commands: index(commands),
        skills: index(skills),
    };
    node(&idx, kind, slug, &HashSet::new())
}

fn node(
    idx: &Index<'_>,
    kind: NextStepKind,
    slug: &str,
    path: &HashSet<String>,
) -> Option<AgentFlowNode> {
    type Base<'a> = (
        &'a str,
        &'a Option<String>,
        &'a Option<ProviderSettingsMap>,
        Option<String>,
        &'a str,
        &'a [NextStep],
    );
    let base: Base<'_> = match kind {
        NextStepKind::Agent => {
            let a = idx.agents.get(slug)?;
            (
                &a.title,
                &a.model,
                &a.provider_settings,
                None,
                &a.prompt,
                &a.next_steps,
            )
        }
        NextStepKind::Command => {
            let c = idx.commands.get(slug)?;
            (
                &c.title,
                &c.model,
                &c.provider_settings,
                c.argument_hint.clone(),
                &c.prompt,
                &c.next_steps,
            )
        }
        NextStepKind::Skill => {
            let s = idx.skills.get(slug)?;
            (
                &s.title,
                &s.model,
                &s.provider_settings,
                None,
                &s.prompt,
                &s.next_steps,
            )
        }
    };
    let mut here = path.clone();
    here.insert(key(kind, slug));
    let next = base
        .5
        .iter()
        .map(|step| {
            let mut out = AgentFlowStep {
                kind: step.kind,
                r#ref: step.r#ref.clone(),
                note: step.note.clone(),
                node: None,
                warning: None,
            };
            if here.contains(&key(step.kind, &step.r#ref)) {
                out.warning = Some(format!("Ciclo: {} já está neste fluxo.", step.r#ref));
            } else if let Some(n) = node(idx, step.kind, &step.r#ref, &here) {
                out.node = Some(Box::new(n));
            } else {
                out.warning = Some(match step.kind {
                    NextStepKind::Agent => format!("Agente não encontrado: {}", step.r#ref),
                    NextStepKind::Command => format!("Comando não encontrado: {}", step.r#ref),
                    NextStepKind::Skill => format!("Skill não encontrada: {}", step.r#ref),
                });
            }
            out
        })
        .collect();
    Some(AgentFlowNode {
        kind,
        r#ref: slug.to_string(),
        title: base.0.to_string(),
        model: base.1.clone(),
        provider_settings: base.2.clone(),
        argument_hint: base.3,
        prompt: base.4.to_string(),
        next,
    })
}

/// JSON do fluxo (VDJSON **com** `\n` final, como `VDJSON.encode`), pronto para colar num prompt.
pub fn flow_json(store: &Store, kind: NextStepKind, slug: &str) -> Result<Option<String>> {
    let agents = store.agents()?;
    let commands = store.commands()?;
    let skills = store.skills()?;
    let Some(n) = build(kind, slug, &agents, &commands, &skills) else {
        return Ok(None);
    };
    let bytes = json::encode(&n).map_err(crate::Error::Encode)?;
    Ok(Some(String::from_utf8_lossy(&bytes).into_owned()))
}

/// Resolve `reference` do tipo e devolve o JSON do fluxo (`""` se nulo).
pub fn flow_for(store: &Store, kind: NextStepKind, reference: &str) -> Result<String> {
    let slug = match kind {
        NextStepKind::Agent => store.resolve::<Agent>(reference)?,
        NextStepKind::Command => store.resolve::<Command>(reference)?,
        NextStepKind::Skill => store.resolve::<Skill>(reference)?,
    };
    Ok(flow_json(store, kind, &slug)?.unwrap_or_default())
}
