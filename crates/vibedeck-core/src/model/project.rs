//! `vibedeck.json` — Project (schema `project`).

use serde::{Deserialize, Deserializer, Serialize};

use super::common::*;

pub const SCHEMA_BASE: &str = "https://vibedeck-schema.alanreisanjo.workers.dev/v1";

pub fn schema_url(name: &str) -> String {
    format!("{SCHEMA_BASE}/{name}.schema.json")
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewKind {
    pub id: String,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub symbol: Option<String>,
}

impl ReviewKind {
    /// Os 6 tipos padrão (usados quando `reviewKinds` falta ou está vazio).
    pub fn defaults() -> Vec<ReviewKind> {
        [
            ("disable", "Inativar", "nosign"),
            ("hide", "Ocultar", "eye.slash"),
            ("fix", "Corrigir", "wrench.and.screwdriver"),
            ("change", "Alterar", "pencil"),
            ("remove", "Remover", "trash"),
            ("note", "Nota", "note.text"),
        ]
        .into_iter()
        .map(|(id, label, symbol)| ReviewKind {
            id: id.into(),
            label: label.into(),
            symbol: Some(symbol.into()),
        })
        .collect()
    }
}

fn de_review_kinds<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<ReviewKind>, D::Error> {
    let v: Vec<ReviewKind> = nd(d)?;
    Ok(if v.is_empty() {
        ReviewKind::defaults()
    } else {
        v
    })
}

fn de_version<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(Option::<i64>::deserialize(d)?.unwrap_or(1))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(default = "default_version", deserialize_with = "de_version")]
    pub version: i64,
    #[serde(default, deserialize_with = "nd")]
    pub id: Id,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Sempre gravado, mesmo vazio.
    #[serde(default, deserialize_with = "nd")]
    pub links: Vec<Link>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub claude: Vec<ClaudeItem>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub stack: Vec<StackItem>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub patterns: Vec<ProjectPattern>,
    /// `codexCloudEnvironment` (D5) é ignorado na leitura e nunca emitido.
    #[serde(default = "ReviewKind::defaults", deserialize_with = "de_review_kinds")]
    pub review_kinds: Vec<ReviewKind>,
}

fn default_version() -> i64 {
    1
}

impl Project {
    pub fn new(name: impl Into<String>, description: Option<String>) -> Self {
        Project {
            schema: Some(schema_url("project")),
            version: 1,
            id: Id::new(),
            name: name.into(),
            description,
            links: vec![],
            claude: vec![],
            stack: vec![],
            patterns: vec![],
            review_kinds: ReviewKind::defaults(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "LinkWire")]
pub struct Link {
    pub id: Id,
    pub title: String,
    pub url: String,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
}

#[derive(Deserialize)]
struct LinkWire {
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    title: Option<String>,
    url: String,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
}

impl From<LinkWire> for Link {
    fn from(w: LinkWire) -> Self {
        Link {
            id: w.id,
            title: w.title.unwrap_or_else(|| w.url.clone()),
            url: w.url,
            tags: w.tags,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClaudeItemKind {
    #[default]
    Artifact,
    Doc,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "ClaudeItemWire", rename_all = "camelCase")]
pub struct ClaudeItem {
    pub id: Id,
    pub title: String,
    pub url: String,
    pub kind: ClaudeItemKind,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    pub added_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeItemWire {
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    title: Option<String>,
    url: String,
    #[serde(default, deserialize_with = "nd")]
    kind: ClaudeItemKind,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    added_at: Timestamp,
}

/// `ClaudeItem.suggestedTitle`: fonte única em `project::claude` (inclui o trim de `/` final).
pub fn suggested_claude_title(url: &str) -> String {
    crate::project::claude::suggested_title(url)
}

impl From<ClaudeItemWire> for ClaudeItem {
    fn from(w: ClaudeItemWire) -> Self {
        ClaudeItem {
            id: w.id,
            title: w.title.unwrap_or_else(|| suggested_claude_title(&w.url)),
            url: w.url,
            kind: w.kind,
            tags: w.tags,
            added_at: w.added_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "StackItemWire")]
pub struct StackItem {
    pub icon: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "opt_str_empty")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    pub author: Author,
}

#[derive(Deserialize)]
struct StackItemWire {
    icon: String,
    name: Option<String>,
    category: Option<String>,
    note: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    author: Author,
}

impl From<StackItemWire> for StackItem {
    fn from(w: StackItemWire) -> Self {
        StackItem {
            name: w.name.unwrap_or_else(|| w.icon.clone()),
            icon: w.icon,
            category: w.category,
            note: w.note,
            tags: w.tags,
            author: w.author,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "ProjectPatternWire")]
pub struct ProjectPattern {
    pub id: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "opt_str_empty")]
    pub summary: Option<String>,
    #[serde(skip_serializing_if = "opt_str_empty")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub topic: Option<String>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    pub author: Author,
}

#[derive(Deserialize)]
struct ProjectPatternWire {
    id: String,
    name: Option<String>,
    category: Option<String>,
    summary: Option<String>,
    note: Option<String>,
    topic: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    author: Author,
}

impl From<ProjectPatternWire> for ProjectPattern {
    fn from(w: ProjectPatternWire) -> Self {
        ProjectPattern {
            name: w.name.unwrap_or_else(|| w.id.clone()),
            id: w.id,
            category: w.category,
            summary: w.summary,
            note: w.note,
            topic: w.topic,
            tags: w.tags,
            author: w.author,
        }
    }
}
