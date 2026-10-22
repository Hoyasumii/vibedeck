//! Erros tipados do Core. As mensagens em PT espelham `VibeDeckError` do Swift.

use std::path::PathBuf;

pub type Result<T, E = Error> = std::result::Result<T, E>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Nenhum vibedeck.json encontrado em {0} ou diretórios acima. Rode `vibedeck init`.")]
    NotAProject(String),
    #[error("{0} já contém um vibedeck.json.")]
    AlreadyAProject(String),
    #[error("Grupo de revisão não encontrado: {0}")]
    GroupNotFound(String),
    #[error("Item de revisão não encontrado: {0}")]
    ItemNotFound(String),
    #[error("Prefixo de id ambíguo: {0}")]
    AmbiguousItem(String),
    #[error("Tópico de regras não encontrado: {0}")]
    TopicNotFound(String),
    #[error("Ideia não encontrada: {0}")]
    IdeaNotFound(String),
    #[error("Agente não encontrado: {0}")]
    AgentNotFound(String),
    #[error("Comando não encontrado: {0}")]
    CommandNotFound(String),
    #[error("Skill não encontrada: {0}")]
    SkillNotFound(String),
    #[error("Workflow não encontrado: {0}")]
    WorkflowNotFound(String),
    #[error("Execução de workflow não encontrada: {0}")]
    RunNotFound(String),
    #[error("Check de regras não encontrado: {0}")]
    CheckNotFound(String),
    #[error("Nome inválido.")]
    InvalidName,
    #[error("Caminho de grupo inválido ou fora da pasta do conceito: {0}")]
    InvalidGroupPath(String),
    #[error("Referência ambígua: {reference}. Use um dos caminhos: {}", sorted_join(.paths))]
    AmbiguousReference {
        reference: String,
        paths: Vec<String>,
    },
    #[error("O destino já existe: {0}. Nada foi sobrescrito.")]
    GroupConflict(String),
    #[error("O check {0} já existe; checks são histórico imutável e nunca são reescritos.")]
    CheckExists(String),
    #[error("Erro de E/S em {}: {source}", path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("Não foi possível ler {}: {source}", path.display())]
    Decode {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("Não foi possível serializar o registro: {0}")]
    Encode(#[source] serde_json::Error),
}

fn sorted_join(paths: &[String]) -> String {
    let mut v: Vec<&str> = paths.iter().map(String::as_str).collect();
    v.sort_unstable();
    v.join(", ")
}

impl Error {
    pub(crate) fn io(path: impl Into<PathBuf>, source: std::io::Error) -> Self {
        Error::Io {
            path: path.into(),
            source,
        }
    }
}
