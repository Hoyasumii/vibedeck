//! `reviews/<slug>.json` — ReviewGroup (schema `review-group`).

use serde::{Deserialize, Serialize};

use super::common::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewStatus {
    #[default]
    Open,
    InProgress,
    Done,
    Wontfix,
}

impl ReviewStatus {
    pub fn is_closed(self) -> bool {
        matches!(self, ReviewStatus::Done | ReviewStatus::Wontfix)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReviewPriority {
    Low,
    #[default]
    Normal,
    High,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct ReviewTarget {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub route: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub component: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selector: Option<String>,
}

impl ReviewTarget {
    pub fn is_empty(&self) -> bool {
        self.file.is_none()
            && self.route.is_none()
            && self.component.is_none()
            && self.selector.is_none()
    }
}

fn default_kind() -> String {
    "note".into()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "ReviewItemWire", rename_all = "camelCase")]
pub struct ReviewItem {
    pub id: Id,
    /// Qualquer string é aceita (os tipos válidos vêm de `Project.review_kinds`).
    pub kind: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    pub status: ReviewStatus,
    pub priority: ReviewPriority,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<ReviewTarget>,
    /// Slugs de tópicos de regras.
    #[serde(skip_serializing_if = "vec_empty")]
    pub rules: Vec<String>,
    pub author: Author,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReviewItemWire {
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    kind: Option<String>,
    title: String,
    details: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    status: ReviewStatus,
    #[serde(default, deserialize_with = "nd")]
    priority: ReviewPriority,
    target: Option<ReviewTarget>,
    #[serde(default, deserialize_with = "nd")]
    rules: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    author: Author,
    #[serde(default, deserialize_with = "nd")]
    created_at: Timestamp,
    updated_at: Option<Timestamp>,
}

impl From<ReviewItemWire> for ReviewItem {
    fn from(w: ReviewItemWire) -> Self {
        ReviewItem {
            id: w.id,
            kind: w.kind.unwrap_or_else(default_kind),
            title: w.title,
            details: w.details,
            status: w.status,
            priority: w.priority,
            target: w.target,
            rules: w.rules,
            author: w.author,
            created_at: w.created_at,
            updated_at: w.updated_at.unwrap_or(w.created_at),
        }
    }
}

impl ReviewItem {
    pub fn new(kind: impl Into<String>, title: impl Into<String>) -> Self {
        let now = Timestamp::now();
        ReviewItem {
            id: Id::new(),
            kind: kind.into(),
            title: title.into(),
            details: None,
            status: ReviewStatus::Open,
            priority: ReviewPriority::Normal,
            target: None,
            rules: vec![],
            author: Author::Human,
            created_at: now,
            updated_at: now,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewGroup {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub id: Id,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, deserialize_with = "nd", skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    pub created_at: Timestamp,
    /// Sempre gravado, mesmo vazio.
    #[serde(default, deserialize_with = "nd")]
    pub items: Vec<ReviewItem>,
}

impl ReviewGroup {
    pub fn new(title: impl Into<String>) -> Self {
        ReviewGroup {
            schema: Some(super::project::schema_url("review-group")),
            id: Id::new(),
            title: title.into(),
            description: None,
            tags: vec![],
            created_at: Timestamp::now(),
            items: vec![],
        }
    }
}
