//! Projeto: init, status, links, coleção Claude (claude items), tags, grafo (export) e logs.
//!
//! Tudo aqui é usado pelo CLI e pelo MCP do mesmo jeito (um caso de uso, dois adaptadores).

pub mod claude;
pub mod graph;
pub mod links;
pub mod logs;
pub mod markdown;
pub mod status;
pub mod tags;

use std::path::{Path, PathBuf};

use crate::paths;
use crate::store::Store;

pub use status::{GroupSummary, Overview, Status, Summary};

/// Erros da área; as mensagens espelham `VibeDeckError` do Swift.
#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("Informe uma URL http ou https do claude.ai.")]
    InvalidClaudeUrl,
    #[error("Item do Claude não encontrado: {0}")]
    ClaudeItemNotFound(String),
    #[error("Referência do Claude ambígua: {0}")]
    AmbiguousClaudeItem(String),
    #[error("Link não encontrado: {0}")]
    LinkNotFound(String),
    #[error("Doc não encontrado: {0}")]
    DocNotFound(String),
    #[error("Tecnologia não encontrada na stack: {0}")]
    StackItemNotFound(String),
    #[error("Padrão não encontrado no projeto: {0}")]
    PatternNotFound(String),
    #[error("Tipo inválido: {0}")]
    InvalidTagKind(String),
    #[error("Grafo: {0}")]
    Graph(String),
    #[error("Filtro de log inválido: {0}. Use, por exemplo, 30m, 24h ou 7d.")]
    InvalidLogFilter(String),
    #[error("Não foi possível gravar o log: {0}")]
    LogUnavailable(String),
    #[error(transparent)]
    Core(#[from] crate::Error),
}

pub type Result<T, E = ProjectError> = std::result::Result<T, E>;

/// `ProjectStore.initialize`: cria `vibedeck.json` e as pastas de `.vibedeck/`.
///
/// O nome padrão é o da pasta; `name` é aparado e, se ficar vazio, vale o da pasta. Não escreve o guia
/// (`AGENTS.md`/`guide.md`): quem tem o guia embutido usa [`init_with`].
pub fn init(dir: &Path, name: Option<&str>, description: Option<&str>) -> Result<Store> {
    init_with(dir, name, description, |_| Ok(()))
}

/// Como [`init`], mas chama `after` com o store recém-criado (ex.: gravar o guia embutido).
pub fn init_with(
    dir: &Path,
    name: Option<&str>,
    description: Option<&str>,
    after: impl FnOnce(&Store) -> crate::Result<()>,
) -> Result<Store> {
    let root = standard_root(dir);
    let project_name = name
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            root.file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| root.display().to_string())
        });
    let store = Store::init(&root, &project_name, description.map(str::to_string))?;
    after(&store)?;
    Ok(store)
}

/// `URL.standardizedFileURL` sobre um caminho absoluto: resolve `.` e `..` só lexicalmente.
fn standard_root(dir: &Path) -> PathBuf {
    let abs = std::path::absolute(dir).unwrap_or_else(|_| dir.to_path_buf());
    paths::lexical_normalize(&abs)
}
