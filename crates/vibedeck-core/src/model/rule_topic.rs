//! `rules/<slug>.json` — RuleTopic (schema `rule-topic`), com `Rule` e `RuleTest`.

use serde::{Deserialize, Serialize};

use super::common::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleSeverity {
    #[default]
    Must,
    Should,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleTestMode {
    Script,
    #[default]
    Manual,
}

/// Teste de uma regra. Sem `ruleHash` o teste lê como desatualizado (`""`); sem `mode`, ele segue `command`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "RuleTestWire", rename_all = "camelCase")]
pub struct RuleTest {
    pub mode: RuleTestMode,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    pub rule_hash: String,
    pub generated_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuleTestWire {
    mode: Option<RuleTestMode>,
    command: Option<String>,
    reason: Option<String>,
    rule_hash: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    generated_at: Timestamp,
}

impl From<RuleTestWire> for RuleTest {
    fn from(w: RuleTestWire) -> Self {
        let mode = w.mode.unwrap_or(if w.command.is_none() {
            RuleTestMode::Manual
        } else {
            RuleTestMode::Script
        });
        RuleTest {
            mode,
            command: w.command,
            reason: w.reason,
            rule_hash: w.rule_hash.unwrap_or_default(),
            generated_at: w.generated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Rule {
    #[serde(default, deserialize_with = "nd")]
    pub id: Id,
    pub text: String,
    /// Caminho aninhado dentro do tópico (só organização).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub severity: RuleSeverity,
    #[serde(default, deserialize_with = "nd")]
    pub author: Author,
    #[serde(default, deserialize_with = "nd")]
    pub created_at: Timestamp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub test: Option<RuleTest>,
}

impl Rule {
    pub fn new(text: impl Into<String>) -> Self {
        Rule {
            id: Id::new(),
            text: text.into(),
            group: None,
            details: None,
            severity: RuleSeverity::Must,
            author: Author::Human,
            created_at: Timestamp::now(),
            test: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleTopic {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub id: Id,
    pub title: String,
    /// Sempre gravado (a regravação do Swift acrescenta `"author": "human"` quando faltava).
    #[serde(default, deserialize_with = "nd")]
    pub author: Author,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    /// Globs; vazio = tópico global.
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub paths: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    pub rules: Vec<Rule>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_idea: Option<Id>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_pattern: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub created_at: Timestamp,
}

impl RuleTopic {
    pub fn new(title: impl Into<String>) -> Self {
        RuleTopic {
            schema: Some(super::project::schema_url("rule-topic")),
            id: Id::new(),
            title: title.into(),
            author: Author::Human,
            description: None,
            tags: vec![],
            paths: vec![],
            rules: vec![],
            source_idea: None,
            source_pattern: None,
            created_at: Timestamp::now(),
        }
    }

    pub fn is_global(&self) -> bool {
        self.paths.is_empty()
    }
}
