//! Início guiado (MUD-001): detecção e cadastro de recursos existentes.
//!
//! Decisão D3: dispara em "Novo projeto" ou pasta sem `vibedeck.json`; "Pular" é retomável; varre
//! `.claude/{agents,commands,skills}`, `.codex/prompts` e `.codex/agents`; duplicados aparecem como
//! já cadastrados; recusar não cria registros; nada é importado ou sobrescrito automaticamente.
//!
//! Estado persistido em `.vibedeck/onboarding.json` (`{"status": "pending|skipped|done", "updatedAt": ...}`),
//! arquivo aditivo: o `vibedeck.json` tipado descarta chaves desconhecidas a cada gravação, então um campo
//! lá se perderia. Ausente = estado implícito (ver [`Report::persisted`]).

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::error::Error;
use crate::model::{Author, NextStepKind};
use crate::resources::import::{Discovered, discover, import_discovered};
use crate::{Store, json, store, time};

pub const STATE_FILE: &str = "onboarding.json";

#[derive(Debug, thiserror::Error)]
pub enum OnboardingError {
    #[error("Item inválido: {0}. Use <tipo>:<nome> com tipo agent, command ou skill.")]
    InvalidItem(String),
    #[error(
        "Recurso não encontrado entre os detectados: {0}. Nada foi cadastrado. Veja `vibedeck onboarding`."
    )]
    NotFound(String),
    #[error(transparent)]
    Core(#[from] Error),
    #[error("{0}")]
    Resources(String),
}

pub type Result<T> = std::result::Result<T, OnboardingError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pending,
    Skipped,
    Done,
}

impl Status {
    pub fn label(self) -> &'static str {
        match self {
            Status::Pending => "pending",
            Status::Skipped => "skipped",
            Status::Done => "done",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub status: Status,
    pub updated_at: String,
}

/// Etapa sugerida do fluxo guiado.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Step {
    Stack,
    Patterns,
    Resources,
    Done,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PatternView {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ResourceView {
    /// `agent`, `command` ou `skill`.
    pub kind: &'static str,
    /// `claude` ou `codex`.
    pub provider: &'static str,
    pub name: String,
    pub slug: String,
    /// Caminho de origem relativo à raiz do projeto.
    pub origin: String,
    /// Já existe em `.vibedeck/`: aparece como "já cadastrado" e desmarcado.
    pub registered: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    /// `false` em pasta sem `vibedeck.json` (início guiado dispara; só leitura).
    pub has_project: bool,
    pub status: Status,
    /// `false` quando o estado é implícito (nunca gravado).
    pub persisted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    /// O app/IA deve perguntar agora (`status == pending`).
    pub should_prompt: bool,
    pub step: Step,
    pub stack_empty: bool,
    pub stack: Vec<String>,
    /// Stack deduzida dos arquivos da raiz (Cargo.toml -> Rust etc.), sem o que já está na `stack`.
    pub suggested_stack: Vec<String>,
    pub patterns: Vec<PatternView>,
    pub resources: Vec<ResourceView>,
}

/// Arquivo da raiz -> nome de stack sugerido (ordem estável).
const STACK_MARKERS: [(&str, &str); 14] = [
    ("Cargo.toml", "Rust"),
    ("Package.swift", "Swift"),
    ("go.mod", "Go"),
    ("pyproject.toml", "Python"),
    ("requirements.txt", "Python"),
    ("Gemfile", "Ruby"),
    ("pom.xml", "Java"),
    ("build.gradle", "Java"),
    ("build.gradle.kts", "Kotlin"),
    ("composer.json", "PHP"),
    ("pubspec.yaml", "Dart"),
    ("mix.exs", "Elixir"),
    ("tsconfig.json", "TypeScript"),
    ("Dockerfile", "Docker"),
];

/// Sugere stack pelos arquivos de manifesto da raiz. `package.json` vira TypeScript quando há `tsconfig.json`
/// ou a dependência `typescript`; senão Node. Fora do que `existing` já tem (sem diferenciar caixa).
pub fn suggest_stack(root: &Path, existing: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut add = |name: &str| {
        let known = existing
            .iter()
            .chain(out.iter())
            .any(|e| e.eq_ignore_ascii_case(name));
        if !known {
            out.push(name.to_string());
        }
    };
    let package = fs::read_to_string(root.join("package.json")).ok();
    if let Some(text) = &package {
        let typed = root.join("tsconfig.json").is_file() || text.contains("\"typescript\"");
        add(if typed { "TypeScript" } else { "Node" });
    }
    for (file, name) in STACK_MARKERS {
        if root.join(file).is_file() {
            add(name);
        }
    }
    if let Ok(rd) = fs::read_dir(root)
        && rd
            .flatten()
            .any(|e| e.file_name().to_string_lossy().ends_with(".csproj"))
    {
        add("C#");
    }
    out
}

pub fn kind_label(kind: NextStepKind) -> &'static str {
    match kind {
        NextStepKind::Agent => "agent",
        NextStepKind::Command => "command",
        NextStepKind::Skill => "skill",
    }
}

fn provider_label(p: crate::model::AiProvider) -> &'static str {
    match p {
        crate::model::AiProvider::Claude => "claude",
        crate::model::AiProvider::Codex => "codex",
    }
}

fn state_path(root: &Path) -> std::path::PathBuf {
    root.join(store::DATA_DIR).join(STATE_FILE)
}

/// Estado gravado, se houver e for legível.
pub fn load_state(root: &Path) -> Option<State> {
    serde_json::from_slice(&fs::read(state_path(root)).ok()?).ok()
}

fn write_state(store: &Store, status: Status) -> Result<State> {
    let state = State {
        status,
        updated_at: time::format_iso(time::now()),
    };
    let bytes = json::encode(&state).map_err(Error::Encode)?;
    store::write_atomic(&state_path(store.root()), &bytes)?;
    Ok(state)
}

/// Relatório para uma raiz que pode ainda não ser projeto (não escreve nada).
pub fn status_at(root: &Path) -> Report {
    let project = Store::open(root).ok().and_then(|s| s.project().ok());
    let has_project = Store::open(root).is_ok();
    let stack: Vec<String> = project
        .as_ref()
        .map(|p| p.stack.iter().map(|s| s.name.clone()).collect())
        .unwrap_or_default();
    let patterns: Vec<PatternView> = project
        .as_ref()
        .map(|p| {
            p.patterns
                .iter()
                .map(|x| PatternView {
                    id: x.id.clone(),
                    name: x.name.clone(),
                })
                .collect()
        })
        .unwrap_or_default();
    let resources: Vec<ResourceView> = discover(root).into_iter().map(|d| view(root, d)).collect();
    let stored = if has_project { load_state(root) } else { None };
    // Sem estado gravado: projeto que já tem stack ou padrões conta como concluído (não incomoda);
    // pasta nova ou projeto vazio fica pendente.
    let status = match &stored {
        Some(s) => s.status,
        None if has_project && (!stack.is_empty() || !patterns.is_empty()) => Status::Done,
        None => Status::Pending,
    };
    let step = if stack.is_empty() {
        Step::Stack
    } else if patterns.is_empty() {
        Step::Patterns
    } else if resources.iter().any(|r| !r.registered) {
        Step::Resources
    } else {
        Step::Done
    };
    let suggested_stack = suggest_stack(root, &stack);
    Report {
        has_project,
        status,
        persisted: stored.is_some(),
        updated_at: stored.map(|s| s.updated_at),
        should_prompt: status == Status::Pending,
        step,
        stack_empty: stack.is_empty(),
        stack,
        suggested_stack,
        patterns,
        resources,
    }
}

pub fn status(store: &Store) -> Report {
    status_at(store.root())
}

fn view(root: &Path, d: Discovered) -> ResourceView {
    ResourceView {
        kind: kind_label(d.kind),
        provider: provider_label(d.provider),
        origin: d
            .origin
            .strip_prefix(root)
            .unwrap_or(&d.origin)
            .to_string_lossy()
            .into_owned(),
        name: d.name,
        slug: d.slug,
        registered: d.registered,
    }
}

/// "Pular por agora": retomável; não cria registros.
pub fn skip(store: &Store) -> Result<State> {
    write_state(store, Status::Skipped)
}

/// Marca o início guiado como concluído.
pub fn complete(store: &Store) -> Result<State> {
    write_state(store, Status::Done)
}

/// Item escolhido: `<tipo>:<nome>` (nome ou slug do recurso detectado).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemRef {
    pub kind: NextStepKind,
    pub name: String,
}

impl ItemRef {
    pub fn parse(text: &str) -> Result<ItemRef> {
        let bad = || OnboardingError::InvalidItem(text.to_string());
        // O nome pode conter ':' (comandos em subpastas viram `ns:nome`): divide só no primeiro.
        let (kind, name) = text.split_once(':').ok_or_else(bad)?;
        let kind = match kind.trim().to_lowercase().as_str() {
            "agent" | "agents" | "agente" | "agentes" => NextStepKind::Agent,
            "command" | "commands" | "comando" | "comandos" => NextStepKind::Command,
            "skill" | "skills" => NextStepKind::Skill,
            _ => return Err(bad()),
        };
        let name = name.trim();
        if name.is_empty() {
            return Err(bad());
        }
        Ok(ItemRef {
            kind,
            name: name.to_string(),
        })
    }

    fn matches(&self, d: &Discovered) -> bool {
        d.kind == self.kind
            && (d.name == self.name
                || d.slug == self.name
                || d.slug == crate::slug::make(&self.name))
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Outcome {
    /// `tipo:slug` cadastrados agora.
    pub imported: Vec<String>,
    /// `tipo:slug` que já estavam cadastrados (nada foi alterado).
    pub already_registered: Vec<String>,
    pub warnings: Vec<String>,
}

/// Cadastra só os itens escolhidos. Valida tudo antes de gravar (item desconhecido = nada é cadastrado);
/// já cadastrados são ignorados, nunca sobrescritos.
pub fn import_selected(store: &Store, items: &[ItemRef], author: Author) -> Result<Outcome> {
    let found = discover(store.root());
    let mut chosen: Vec<Discovered> = Vec::new();
    for item in items {
        let d = found.iter().find(|d| item.matches(d)).ok_or_else(|| {
            OnboardingError::NotFound(format!("{}:{}", kind_label(item.kind), item.name))
        })?;
        if !chosen.iter().any(|c| c.kind == d.kind && c.slug == d.slug) {
            chosen.push(d.clone());
        }
    }
    let mut out = Outcome::default();
    let mut fresh = Vec::new();
    for d in chosen {
        let label = format!("{}:{}", kind_label(d.kind), d.slug);
        // Reconfere em disco: outro processo pode ter cadastrado desde a descoberta.
        let exists = store
            .data_dir()
            .join(dir_of(d.kind))
            .join(format!("{}.json", d.slug))
            .exists();
        if d.registered || exists {
            out.already_registered.push(label);
        } else {
            fresh.push(d);
        }
    }
    let result = import_discovered(store, &fresh, false, author)
        .map_err(|e| OnboardingError::Resources(e.to_string()))?;
    out.warnings = result.warnings;
    out.imported = fresh
        .iter()
        .filter(|d| result.slugs.contains(&d.slug))
        .map(|d| format!("{}:{}", kind_label(d.kind), d.slug))
        .collect();
    Ok(out)
}

fn dir_of(kind: NextStepKind) -> &'static str {
    match kind {
        NextStepKind::Agent => "agents",
        NextStepKind::Command => "commands",
        NextStepKind::Skill => "skills",
    }
}
