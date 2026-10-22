//! `runs/<workflow>/<run>/run.json` — WorkflowRun (schema `workflow-run`).

use serde::{Deserialize, Serialize};

use super::common::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AiProvider {
    #[default]
    Claude,
    Codex,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WorkflowRunStatus {
    #[default]
    Running,
    Waiting,
    Done,
    Stopped,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkflowStepCheckpoint {
    pub step: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verdict: Option<String>,
    pub output: String,
    pub completed: bool,
}

fn one() -> i64 {
    1
}

fn de_cycle<'de, D: serde::Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(Option::<i64>::deserialize(d)?.unwrap_or(1))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkflowRunEntry {
    pub step: String,
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
    pub summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next: Option<String>,
    #[serde(default = "one", deserialize_with = "de_cycle")]
    pub cycle: i64,
    #[serde(default, deserialize_with = "nd")]
    pub at: Timestamp,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkflowQuestionOption {
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowQuestion {
    pub number: i64,
    pub step: String,
    pub question: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<String>,
    /// Sempre gravado, mesmo vazio.
    #[serde(default, deserialize_with = "nd")]
    pub options: Vec<WorkflowQuestionOption>,
    /// Sempre gravado.
    #[serde(default, deserialize_with = "nd")]
    pub multiple: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answer: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    pub created_at: Timestamp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answered_at: Option<Timestamp>,
}

impl WorkflowQuestion {
    pub fn is_open(&self) -> bool {
        self.answer.is_none()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "WorkflowRunWire", rename_all = "camelCase")]
pub struct WorkflowRun {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    pub id: Id,
    /// Slug do workflow.
    pub workflow: String,
    pub provider: AiProvider,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input: Option<String>,
    pub status: WorkflowRunStatus,
    /// Etapa a executar; ausente quando terminou.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    pub cycle: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint: Option<WorkflowStepCheckpoint>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub history: Vec<WorkflowRunEntry>,
    #[serde(skip_serializing_if = "vec_empty")]
    pub questions: Vec<WorkflowQuestion>,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowRunWire {
    #[serde(rename = "$schema")]
    schema: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    id: Id,
    workflow: String,
    #[serde(default, deserialize_with = "nd")]
    provider: AiProvider,
    input: Option<String>,
    #[serde(default, deserialize_with = "nd")]
    status: WorkflowRunStatus,
    current: Option<String>,
    reason: Option<String>,
    #[serde(default = "one", deserialize_with = "de_cycle")]
    cycle: i64,
    checkpoint: Option<WorkflowStepCheckpoint>,
    #[serde(default, deserialize_with = "nd")]
    history: Vec<WorkflowRunEntry>,
    #[serde(default, deserialize_with = "nd")]
    questions: Vec<WorkflowQuestion>,
    #[serde(default, deserialize_with = "nd")]
    created_at: Timestamp,
    updated_at: Option<Timestamp>,
}

impl From<WorkflowRunWire> for WorkflowRun {
    fn from(w: WorkflowRunWire) -> Self {
        WorkflowRun {
            schema: w.schema,
            id: w.id,
            workflow: w.workflow,
            provider: w.provider,
            input: w.input,
            status: w.status,
            current: w.current,
            reason: w.reason,
            cycle: w.cycle,
            checkpoint: w.checkpoint,
            history: w.history,
            questions: w.questions,
            created_at: w.created_at,
            updated_at: w.updated_at.unwrap_or(w.created_at),
        }
    }
}
