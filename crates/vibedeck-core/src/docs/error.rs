//! Erros da área de Docs/grupos que o `Error` do Core ainda não tem (mensagens idênticas às do Swift).
//!
//! PEDIDO-INTEGRAÇÃO: quando `error.rs` ganhar `DocNotFound`, `GroupConfirmationRequired`, `RuleNotFound` e
//! `AmbiguousRule`, este tipo pode ser trocado por `Error`.

use crate::error::Error;

pub type Result<T, E = DocError> = std::result::Result<T, E>;

#[derive(Debug, thiserror::Error)]
pub enum DocError {
    #[error(transparent)]
    Core(#[from] Error),
    #[error("Doc não encontrado: {0}")]
    DocNotFound(String),
    #[error("O grupo {0} contém itens. Confirme explicitamente a exclusão.")]
    GroupConfirmationRequired(String),
    #[error("Regra não encontrada entre as aplicáveis: {0}")]
    RuleNotFound(String),
    #[error("Prefixo de id de regra ambíguo: {0}")]
    AmbiguousRule(String),
    #[error(
        "O doc vinculado {slug} está quebrado: a origem {target} não existe. Remova só o vínculo (`vibedeck docs unlink {slug}`)."
    )]
    BrokenLink { slug: String, target: String },
    #[error("O doc {0} não é um vínculo com um .md da raiz; nada foi removido.")]
    NotLinked(String),
    #[error("{0} não é um .md regular na raiz do projeto; nada foi vinculado.")]
    NotRootMarkdown(String),
    #[error(
        "A IA retornou uma proposta de documentos inválida. Nenhum documento foi criado. Tente gerar novamente."
    )]
    InvalidAnswer,
}

impl DocError {
    pub fn invalid_path(path: impl Into<String>) -> Self {
        DocError::Core(Error::InvalidGroupPath(path.into()))
    }

    pub fn io(path: impl Into<std::path::PathBuf>, source: std::io::Error) -> Self {
        DocError::Core(Error::io(path, source))
    }
}
