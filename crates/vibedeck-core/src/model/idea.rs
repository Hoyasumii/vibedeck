//! `ideas/<grupo/>/<slug>.json` — Idea (schema `idea`).

use std::collections::HashSet;

use serde::{Deserialize, Deserializer, Serialize};

use super::common::*;
use super::rule_topic::Rule;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum IdeaStatus {
    #[default]
    New,
    Exploring,
    Approved,
    Discarded,
    Done,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaReadiness {
    #[serde(default, deserialize_with = "nd")]
    pub viable: bool,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub missing: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    pub checked_at: Timestamp,
    #[serde(default, deserialize_with = "nd")]
    pub fingerprint: String,
}

/// `try?`: valor malformado é descartado em silêncio (vira `None`).
fn de_readiness<'de, D: Deserializer<'de>>(d: D) -> Result<Option<IdeaReadiness>, D::Error> {
    let v = Option::<serde_json::Value>::deserialize(d)?;
    Ok(v.and_then(|v| serde_json::from_value(v).ok()))
}

/// Remove duplicatas mantendo a primeira ocorrência.
fn de_dependencies<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<Id>, D::Error> {
    let v: Vec<Id> = nd(d)?;
    let mut seen = HashSet::new();
    Ok(v.into_iter().filter(|i| seen.insert(*i)).collect())
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "IdeaWire", rename_all = "camelCase")]
pub struct Idea {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    pub id: Id,
    pub title: String,
    /// Markdown.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    pub status: IdeaStatus,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub paths: Vec<String>,
    /// Rascunho de regras; sempre gravado.
    pub rules: Vec<Rule>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub promoted_topic: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub readiness: Option<IdeaReadiness>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub dependencies: Vec<Id>,
    pub author: Author,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdeaWire {
    #[serde(rename = "$schema")]
    schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    title: String,
    body: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    status: IdeaStatus,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    paths: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    rules: Vec<Rule>,
    promoted_topic: Option<String>,
    #[serde(default, deserialize_with = "de_readiness")]
    readiness: Option<IdeaReadiness>,
    #[serde(default, deserialize_with = "de_dependencies")]
    dependencies: Vec<Id>,
    #[serde(default, deserialize_with = "nd")]
    author: Author,
    #[serde(default, deserialize_with = "nd")]
    created_at: Timestamp,
    updated_at: Option<Timestamp>,
}

impl From<IdeaWire> for Idea {
    fn from(w: IdeaWire) -> Self {
        Idea {
            schema: w.schema,
            id: w.id,
            title: w.title,
            body: w.body,
            status: w.status,
            tags: w.tags,
            paths: w.paths,
            rules: w.rules,
            promoted_topic: w.promoted_topic,
            readiness: w.readiness,
            dependencies: w.dependencies,
            author: w.author,
            created_at: w.created_at,
            updated_at: w.updated_at.unwrap_or(w.created_at),
        }
    }
}

impl Idea {
    pub fn new(title: impl Into<String>) -> Self {
        let now = Timestamp::now();
        Idea {
            schema: Some(super::project::schema_url("idea")),
            id: Id::new(),
            title: title.into(),
            body: None,
            status: IdeaStatus::New,
            tags: vec![],
            paths: vec![],
            rules: vec![],
            promoted_topic: None,
            readiness: None,
            dependencies: vec![],
            author: Author::Human,
            created_at: now,
            updated_at: now,
        }
    }
}
