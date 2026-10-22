//! Erros da área `resources`: os do Core mais os que só ela produz (`VibeDeckError` do Swift).
//!
//! PEDIDO-INTEGRAÇÃO: mover as variantes abaixo para `crate::Error` quando o integrador mexer em `error.rs`.

use crate::Error;

#[derive(Debug, thiserror::Error)]
pub enum ResourceError {
    #[error(transparent)]
    Core(#[from] Error),
    #[error("Próximo passo inválido: {0}")]
    InvalidNextStep(String),
    #[error("Seleção de kit inválida: {0}. Consulte o catálogo e selecione pelo menos um item.")]
    InvalidKitSelection(String),
    #[error("Selecione também as dependências: {}", .0.join(", "))]
    MissingKitDependencies(Vec<String>),
    /// `VibeDeckError.discoverFailed`.
    #[error("O Claude Code não conseguiu descobrir; nada foi alterado.{}", discover_suffix(.0))]
    DiscoverFailed(String),
    /// Falha de leitura de um arquivo de provedor (`CodexRPCError.server`): "Codex: <mensagem>".
    #[error("Codex: {0}")]
    Codex(String),
    /// Falha de leitura de um provedor sem Codex disponível (listagem de skills do Codex).
    #[error("{0}")]
    Unavailable(String),
}

fn discover_suffix(output: &str) -> String {
    if output.is_empty() {
        String::new()
    } else {
        format!("\n{output}")
    }
}

pub type Result<T, E = ResourceError> = std::result::Result<T, E>;
