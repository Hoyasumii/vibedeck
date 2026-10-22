//! `workflows/<slug>.json` — Workflow (schema `workflow`).

use serde::{Deserialize, Deserializer, Serialize};

use super::common::*;
use super::persona::NextStepKind;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkflowTransition {
    #[serde(
        default,
        deserialize_with = "de_trim_non_empty",
        skip_serializing_if = "Option::is_none"
    )]
    pub verdict: Option<String>,
    #[serde(
        default,
        deserialize_with = "de_trim_non_empty",
        skip_serializing_if = "Option::is_none"
    )]
    pub when: Option<String>,
    pub to: String,
}

/// `maxVisits <= 0` é descartado.
fn de_positive<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i64>, D::Error> {
    Ok(Option::<i64>::deserialize(d)?.filter(|n| *n > 0))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "WorkflowStepWire", rename_all = "camelCase")]
pub struct WorkflowStep {
    pub id: String,
    pub kind: NextStepKind,
    pub r#ref: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_visits: Option<i64>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub transitions: Vec<WorkflowTransition>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowStepWire {
    #[serde(default, deserialize_with = "de_trim_non_empty")]
    id: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    kind: NextStepKind,
    r#ref: String,
    note: Option<String>,
    #[serde(default, deserialize_with = "de_positive")]
    max_visits: Option<i64>,
    #[serde(default, deserialize_with = "nd")]
    transitions: Vec<WorkflowTransition>,
}

impl From<WorkflowStepWire> for WorkflowStep {
    fn from(w: WorkflowStepWire) -> Self {
        WorkflowStep {
            id: w.id.unwrap_or_else(|| w.r#ref.clone()),
            kind: w.kind,
            r#ref: w.r#ref,
            note: w.note,
            max_visits: w.max_visits,
            transitions: w.transitions,
        }
    }
}

pub const DEFAULT_MAX_STEPS: i64 = 25;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "WorkflowWire", rename_all = "camelCase")]
pub struct Workflow {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    pub id: Id,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_steps: Option<i64>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub steps: Vec<WorkflowStep>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub tags: Vec<String>,
    pub author: Author,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowWire {
    #[serde(rename = "$schema")]
    schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    title: String,
    summary: Option<String>,
    input: Option<String>,
    max_steps: Option<i64>,
    #[serde(default, deserialize_with = "nd")]
    steps: Vec<WorkflowStep>,
    #[serde(default, deserialize_with = "nd")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "nd")]
    author: Author,
    #[serde(default, deserialize_with = "nd")]
    created_at: Timestamp,
    updated_at: Option<Timestamp>,
}

impl From<WorkflowWire> for Workflow {
    fn from(w: WorkflowWire) -> Self {
        Workflow {
            schema: w.schema,
            id: w.id,
            title: w.title,
            summary: w.summary,
            input: w.input,
            max_steps: w.max_steps,
            steps: w.steps,
            tags: w.tags,
            author: w.author,
            created_at: w.created_at,
            updated_at: w.updated_at.unwrap_or(w.created_at),
        }
    }
}

impl Workflow {
    pub fn new(title: impl Into<String>) -> Self {
        let now = Timestamp::now();
        Workflow {
            schema: Some(super::project::schema_url("workflow")),
            id: Id::new(),
            title: title.into(),
            summary: None,
            input: None,
            max_steps: None,
            steps: vec![],
            tags: vec![],
            author: Author::Human,
            created_at: now,
            updated_at: now,
        }
    }
}
