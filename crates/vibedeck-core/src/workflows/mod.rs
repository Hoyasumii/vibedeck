//! Workflows e execuções (runs): máquina de estados sobre agentes, comandos e skills do projeto.
//!
//! Porta de `Workflows.swift`, `WorkflowRuns.swift`, da parte Core de `AIWorkflowRunner.swift` e das
//! operações de workflow/run de `ProjectStore.swift`. CLI e MCP chamam as mesmas funções daqui.
//!
//! - `ext`: métodos de domínio dos modelos (transição, etapa, workflow, run).
//! - `engine`: máquina de estados pura sobre um `WorkflowRun` (sem disco).
//! - `plan`: JSON que orquestra a IA (`workflow_flow`).
//! - `prompts`: prompt da etapa e do orquestrador.
//! - `ops`: operações com o `Store` (criação/edição de workflows, ciclo de vida das execuções).

mod engine;
mod error;
mod ext;
mod ops;
mod plan;
mod prompts;

pub use engine::{RunAction, RunActionKind};
pub use engine::{
    answer as engine_answer, ask as engine_ask, next as engine_next, record as engine_record,
    restart as engine_restart, restart_from_beginning, stop as engine_stop,
};
pub use error::{Result, WorkflowError};
pub use ext::{kind_str, provider_str, status_str};
pub use ops::*;
pub use plan::{WorkflowPlan, WorkflowPlanStep};
pub use prompts::{expected_verdicts, orchestrator_prompt, step_prompt};

use serde::{Deserialize, Serialize};

use crate::model::WorkflowQuestionOption;

/// O que uma etapa envia a `ask`: uma pergunta antes de receber número e etapa.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct WorkflowQuestionDraft {
    pub question: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<WorkflowQuestionOption>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub multiple: Option<bool>,
}
