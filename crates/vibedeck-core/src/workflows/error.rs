//! Erros da área. `Invalid` espelha `VibeDeckError.invalidWorkflow`; os demais vêm do core.

use crate::error::Error;

#[derive(Debug, thiserror::Error)]
pub enum WorkflowError {
    #[error("Workflow inválido: {0}")]
    Invalid(String),
    /// Mensagem fixa sem prefixo (ex.: transição inválida do runner de IA).
    #[error("{0}")]
    Plain(String),
    #[error(transparent)]
    Core(#[from] Error),
}

pub type Result<T, E = WorkflowError> = std::result::Result<T, E>;

pub(crate) fn invalid(msg: impl Into<String>) -> WorkflowError {
    WorkflowError::Invalid(msg.into())
}
