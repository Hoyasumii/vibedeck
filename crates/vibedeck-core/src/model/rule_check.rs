//! `checks/<yyyyMMdd-HHmmss>-<id8>.json` — RuleCheck (schema `rule-check`). Histórico imutável.

use serde::{Deserialize, Serialize};

use super::common::*;
use crate::time;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleVerdict {
    Pass,
    Fail,
    Na,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleResultSource {
    #[default]
    Agent,
    Script,
}

impl RuleResultSource {
    fn is_agent(&self) -> bool {
        *self == RuleResultSource::Agent
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleResult {
    pub topic: String,
    pub rule_id: Id,
    pub verdict: RuleVerdict,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Omitido quando `agent`.
    #[serde(
        default,
        deserialize_with = "nd",
        skip_serializing_if = "RuleResultSource::is_agent"
    )]
    pub source: RuleResultSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
}

fn default_ai() -> Author {
    Author::Ai
}

fn de_author_ai<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Author, D::Error> {
    Ok(Option::<Author>::deserialize(d)?.unwrap_or_else(default_ai))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleCheck {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub id: Id,
    #[serde(default, deserialize_with = "nd")]
    pub task: String,
    #[serde(default, deserialize_with = "nd")]
    pub files: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    pub topics: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub review_item: Option<Id>,
    #[serde(default, deserialize_with = "nd")]
    pub results: Vec<RuleResult>,
    #[serde(default, deserialize_with = "nd")]
    pub passed: bool,
    #[serde(default, deserialize_with = "nd")]
    pub warnings: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    pub failures: Vec<String>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub pending: Vec<String>,
    /// Default `ai` (diferente dos demais registros).
    #[serde(default = "default_ai", deserialize_with = "de_author_ai")]
    pub author: Author,
    /// Única data com milissegundos.
    #[serde(default, deserialize_with = "nd")]
    pub created_at: TimestampMs,
}

impl RuleCheck {
    /// Nome do arquivo: `yyyyMMdd-HHmmss-<id8 minúsculo>.json` (GMT).
    pub fn file_name(&self) -> String {
        let id8: String = self.id.to_string().to_lowercase().chars().take(8).collect();
        format!("{}-{id8}.json", time::check_stamp(self.created_at.0))
    }
}
