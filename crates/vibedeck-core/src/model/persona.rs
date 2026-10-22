//! Agent, Command e Skill: mesma forma, com um campo opcional extra cada (`argumentHint`, `sourcePath`).
//! O macro gera a struct pública e o "wire" tolerante (defaults e `updatedAt = createdAt`).

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::common::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NextStepKind {
    #[default]
    Agent,
    Command,
    Skill,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NextStep {
    #[serde(default, deserialize_with = "nd")]
    pub kind: NextStepKind,
    pub r#ref: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct ProviderSettings {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
}

/// Mapa livre provedor → configurações (`claude`, `codex`...); o schema restringe, o código não.
pub type ProviderSettingsMap = BTreeMap<String, ProviderSettings>;

macro_rules! persona {
    (
        $(#[$meta:meta])* $name:ident, $wire:ident, $schema:literal;
        $( $(#[$em:meta])* $extra:ident / $extra_key:literal ),*
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
        #[serde(from = "$wire", rename_all = "camelCase")]
        pub struct $name {
            #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
            pub schema: Option<String>,
            pub id: Id,
            pub title: String,
            #[serde(skip_serializing_if = "Option::is_none")]
            pub summary: Option<String>,
            $(
                $(#[$em])*
                #[serde(rename = $extra_key, skip_serializing_if = "Option::is_none")]
                pub $extra: Option<String>,
            )*
            #[serde(skip_serializing_if = "Option::is_none")]
            pub model: Option<String>,
            #[serde(skip_serializing_if = "Option::is_none")]
            pub provider_settings: Option<ProviderSettingsMap>,
            #[serde(skip_serializing_if = "vec_empty")]
            pub tools: Vec<String>,
            /// Sempre gravado, mesmo vazio.
            pub prompt: String,
            #[serde(skip_serializing_if = "vec_empty")]
            pub next_steps: Vec<NextStep>,
            #[serde(skip_serializing_if = "vec_empty")]
            pub tags: Vec<String>,
            pub author: Author,
            pub created_at: Timestamp,
            pub updated_at: Timestamp,
        }

        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        pub(crate) struct $wire {
            #[serde(rename = "$schema")]
            schema: Option<String>,
            #[serde(default, deserialize_with = "nd")]
            id: Id,
            title: String,
            summary: Option<String>,
            $( #[serde(rename = $extra_key)] $extra: Option<String>, )*
            model: Option<String>,
            provider_settings: Option<ProviderSettingsMap>,
            #[serde(default, deserialize_with = "nd")]
            tools: Vec<String>,
            #[serde(default, deserialize_with = "nd")]
            prompt: String,
            #[serde(default, deserialize_with = "nd")]
            next_steps: Vec<NextStep>,
            #[serde(default, deserialize_with = "nd")]
            tags: Vec<String>,
            #[serde(default, deserialize_with = "nd")]
            author: Author,
            #[serde(default, deserialize_with = "nd")]
            created_at: Timestamp,
            updated_at: Option<Timestamp>,
        }

        impl From<$wire> for $name {
            fn from(w: $wire) -> Self {
                $name {
                    schema: w.schema,
                    id: w.id,
                    title: w.title,
                    summary: w.summary,
                    $( $extra: w.$extra, )*
                    model: w.model,
                    provider_settings: w.provider_settings,
                    tools: w.tools,
                    prompt: w.prompt,
                    next_steps: w.next_steps,
                    tags: w.tags,
                    author: w.author,
                    created_at: w.created_at,
                    updated_at: w.updated_at.unwrap_or(w.created_at),
                }
            }
        }

        impl $name {
            pub fn new(title: impl Into<String>) -> Self {
                let now = Timestamp::now();
                $name {
                    schema: Some(super::project::schema_url($schema)),
                    id: Id::new(),
                    title: title.into(),
                    summary: None,
                    $( $extra: None, )*
                    model: None,
                    provider_settings: None,
                    tools: vec![],
                    prompt: String::new(),
                    next_steps: vec![],
                    tags: vec![],
                    author: Author::Human,
                    created_at: now,
                    updated_at: now,
                }
            }
        }
    };
}

persona!(
    /// `agents/<slug>.json` (schema `agent`).
    Agent, AgentWire, "agent";
);
persona!(
    /// `commands/<slug>.json` (schema `command`).
    Command, CommandWire, "command";
    argument_hint / "argumentHint"
);
persona!(
    /// `skills/<grupo/>/<slug>.json` (schema `skill`). `sourcePath` é absoluto e dependente da máquina.
    Skill, SkillWire, "skill";
    source_path / "sourcePath"
);
