//! IA: guia/AGENTS.md embutido, catálogo, contexto, uso, providers claude/codex, reorganize, item AI.
//!
//! Tudo local: processos `claude` e `codex` (via `codex app-server`, JSON-RPC por stdio). Nada de nuvem (D5).
//! Executáveis de teste: `VIBEDECK_CLAUDE_BIN` e `VIBEDECK_CODEX_BIN` substituem a detecção.

pub mod catalog;
pub mod codex;
pub mod context;
pub mod guide;
pub mod item;
pub mod mcp_install;
pub mod process;
pub mod provider;
pub mod reorganize;
pub mod usage;

mod graphemes;

use std::path::PathBuf;

pub use provider::Provider;

/// Erros da área de IA; as mensagens espelham `VibeDeckError`, `AIIntegrationError`, `ReorganizeError`,
/// `CodexRPCError` e `AIContextError` do Swift.
#[derive(Debug, thiserror::Error)]
pub enum AiError {
    #[error("Referência ou intervalo inválido. Use offset ≥ 0 e limit entre 1 e 16000.")]
    InvalidRange,
    #[error("O Claude Code não conseguiu descobrir; nada foi alterado.{}", discover_suffix(.0))]
    DiscoverFailed(String),
    #[error("O Claude Code respondeu num formato inesperado; nada foi alterado. Tente de novo.")]
    DiscoverInvalidAnswer,
    #[error("O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo.")]
    DiscoverTimedOut,
    #[error("{title} não está instalado.", title = .0.title())]
    Unavailable(Provider),
    #[error("Modelo {0} indisponível no {title}. Escolha outro modelo explicitamente.", title = .1.title())]
    ModelUnavailable(String, Provider),
    #[error("Esforço {0} indisponível para {1}. Escolha outro esforço explicitamente.")]
    EffortUnavailable(String, String),
    #[error("A IA retornou uma proposta de reorganização inválida. Nenhum arquivo foi alterado.")]
    ReorganizeInvalidJson,
    #[error("O projeto mudou. Analise novamente antes de aceitar a reorganização.")]
    ReorganizeStale,
    #[error("A ação ou a escolha de conflito não é válida. Nenhum arquivo foi alterado.")]
    ReorganizeInvalidAction,
    #[error(
        "Os itens têm campos incompatíveis ou protegidos e não podem ser reorganizados desta forma."
    )]
    ReorganizeIncompatible,
    #[error("O destino já está ocupado. Nenhum item será sobrescrito.")]
    ReorganizeOccupied,
    #[error("Já existe uma análise de reorganização em andamento neste projeto.")]
    ReorganizeBusy,
    #[error("Codex não encontrado. Instale o Codex CLI e reabra o VibeDeck.")]
    CodexUnavailable,
    #[error("O Codex encerrou a conexão. Reabra a conversa para tentar novamente.")]
    CodexDisconnected,
    #[error("O Codex não respondeu a {0} a tempo.")]
    CodexTimeout(String),
    #[error("Codex: {0}")]
    CodexServer(String),
    #[error("Resposta inválida do Codex. Verifique a versão do CLI.")]
    CodexInvalidResponse,
    #[error("Entrada da statusline do Claude Code não é um objeto JSON.")]
    InvalidStatusLine,
    #[error("{0} não é um objeto JSON válido; corrija antes de ligar a statusline.")]
    InvalidClaudeSettings(String),
    #[error("Nome inválido.")]
    InvalidName,
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    Core(#[from] crate::Error),
}

fn discover_suffix(output: &str) -> String {
    if output.is_empty() {
        String::new()
    } else {
        format!("\n{output}")
    }
}

impl AiError {
    pub(crate) fn io(path: &std::path::Path, e: std::io::Error) -> Self {
        AiError::Core(crate::Error::Io {
            path: path.to_path_buf(),
            source: e,
        })
    }
}

pub type Result<T, E = AiError> = std::result::Result<T, E>;

/// `~/Library/Application Support` (macOS) ou `$XDG_DATA_HOME`/`~/.local/share`; `VIBEDECK_APP_SUPPORT`
/// (variável de teste) substitui a base.
pub fn app_support_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("VIBEDECK_APP_SUPPORT").filter(|v| !v.is_empty()) {
        return PathBuf::from(dir);
    }
    let home = home_dir();
    if cfg!(target_os = "macos") {
        return home.join("Library/Application Support");
    }
    match std::env::var_os("XDG_DATA_HOME") {
        Some(x) if !x.is_empty() => PathBuf::from(x),
        _ => home.join(".local/share"),
    }
}

/// `VibeDeck/<component>` dentro do diretório de dados da máquina.
pub fn machine_dir(component: &str) -> PathBuf {
    app_support_dir().join("VibeDeck").join(component)
}

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub(crate) fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// `<app support>/VibeDeck/ai/<sha256(raiz real)>`: contexto e uso ficam fora do projeto.
pub fn local_store_dir(root: &std::path::Path) -> PathBuf {
    let real =
        std::fs::canonicalize(root).unwrap_or_else(|_| crate::paths::lexical_normalize(root));
    machine_dir(&format!(
        "ai/{}",
        sha256_hex(real.to_string_lossy().as_bytes())
    ))
}
