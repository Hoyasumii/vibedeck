//! Ideias: CRUD, dependências, readiness, regras rascunho, promoção para tópico de regras.
//!
//! Port de `ProjectStore` (seção Ideas / Idea dependencies) e `IdeaImplementation` do Swift. Tudo é `impl Store`
//! sobre o Store genérico (`Idea` e `RuleTopic`); este módulo não depende de `rules`.

use std::collections::{HashMap, HashSet};
use std::fmt;
use std::path::Path;
use std::str::FromStr;

use regex::Regex;
use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::error::Error;
use crate::model::*;
use crate::store::{Record, Store};

/// Erro dos casos de uso de ideias: os do Core mais os dois que só existem aqui.
#[derive(Debug)]
pub enum IdeaError {
    Core(Error),
    /// `invalidIdeaDependency`: "Dependência inválida: <motivo> Nada foi alterado."
    InvalidDependency(String),
    /// `ideaNotImplementable`.
    NotImplementable(Vec<String>),
}

impl fmt::Display for IdeaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            IdeaError::Core(e) => write!(f, "{e}"),
            IdeaError::InvalidDependency(s) => {
                write!(f, "Dependência inválida: {s} Nada foi alterado.")
            }
            IdeaError::NotImplementable(reasons) => {
                write!(f, "A ideia não pode ser implementada:")?;
                for r in reasons {
                    write!(f, "\n- {r}")?;
                }
                Ok(())
            }
        }
    }
}

impl std::error::Error for IdeaError {}

impl From<Error> for IdeaError {
    fn from(e: Error) -> Self {
        IdeaError::Core(e)
    }
}

pub type IdeaResult<T> = std::result::Result<T, IdeaError>;

/// Valores de texto dos status, na ordem do `CaseIterable` do Swift.
pub const IDEA_STATUSES: [&str; 5] = ["new", "exploring", "approved", "discarded", "done"];

pub trait IdeaStatusExt: Sized {
    fn raw(self) -> &'static str;
    fn label(self) -> &'static str;
    fn is_closed(&self) -> bool;
    fn parse(raw: &str) -> Option<Self>;
}

impl IdeaStatusExt for IdeaStatus {
    fn raw(self) -> &'static str {
        match self {
            IdeaStatus::New => "new",
            IdeaStatus::Exploring => "exploring",
            IdeaStatus::Approved => "approved",
            IdeaStatus::Discarded => "discarded",
            IdeaStatus::Done => "done",
        }
    }

    fn label(self) -> &'static str {
        match self {
            IdeaStatus::New => "Nova",
            IdeaStatus::Exploring => "Explorando",
            IdeaStatus::Approved => "Aprovada",
            IdeaStatus::Discarded => "Descartada",
            IdeaStatus::Done => "Implementada",
        }
    }

    fn is_closed(&self) -> bool {
        matches!(self, IdeaStatus::Discarded | IdeaStatus::Done)
    }

    fn parse(raw: &str) -> Option<Self> {
        Some(match raw {
            "new" => IdeaStatus::New,
            "exploring" => IdeaStatus::Exploring,
            "approved" => IdeaStatus::Approved,
            "discarded" => IdeaStatus::Discarded,
            "done" => IdeaStatus::Done,
            _ => return None,
        })
    }
}

/// `ProjectStore.groupPath(of:)`: tudo antes do último `/`.
pub fn group_path(slug: &str) -> String {
    let parts: Vec<&str> = slug.split('/').filter(|p| !p.is_empty()).collect();
    match parts.split_last() {
        Some((_, head)) => head.join("/"),
        None => String::new(),
    }
}

fn hex8(bytes: &[u8]) -> String {
    Sha256::digest(bytes)[..8]
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// `Rule.contentHash`: 16 hex de SHA-256 de `text + "\n" + details`.
pub fn rule_content_hash(rule: &Rule) -> String {
    hex8(format!("{}\n{}", rule.text, rule.details.as_deref().unwrap_or("")).as_bytes())
}

/// Estado do teste de uma regra, como `Rule.testState`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleTestState {
    None,
    Script,
    Manual,
    Stale,
}

pub fn rule_test_state(rule: &Rule) -> RuleTestState {
    let Some(test) = &rule.test else {
        return RuleTestState::None;
    };
    if test.rule_hash != rule_content_hash(rule) {
        return RuleTestState::Stale;
    }
    let has_command = test
        .command
        .as_deref()
        .is_some_and(|c| !c.trim().is_empty());
    if test.mode == RuleTestMode::Script && has_command {
        RuleTestState::Script
    } else {
        RuleTestState::Manual
    }
}

impl IdeaFingerprint for Idea {
    /// Impressão digital do que a IA julgou (título, corpo, globs, regras). Status, tags, dependências e
    /// promoção ficam de fora.
    fn content_fingerprint(&self) -> String {
        let mut parts: Vec<String> = vec![
            self.title.clone(),
            self.body.clone().unwrap_or_default(),
            self.paths.join("\n"),
        ];
        for r in &self.rules {
            let sev = match r.severity {
                RuleSeverity::Must => "must",
                RuleSeverity::Should => "should",
            };
            parts.push(format!(
                "{sev}\t{}\t{}",
                r.text,
                r.details.as_deref().unwrap_or("")
            ));
        }
        hex8(parts.join("\n\u{1F}\n").as_bytes())
    }
}

pub trait IdeaFingerprint {
    fn content_fingerprint(&self) -> String;
}

/// Ideia referenciada por outra (dependência ou dependente).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct IdeaLink {
    pub id: Id,
    pub slug: String,
    pub title: String,
    pub status: IdeaStatus,
}

impl IdeaLink {
    pub fn new(slug: &str, idea: &Idea) -> Self {
        IdeaLink {
            id: idea.id,
            slug: slug.to_string(),
            title: idea.title.clone(),
            status: idea.status,
        }
    }
}

/// Dependência que impede a implementação: não está `done` ou sumiu do projeto (`idea == None`).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct IdeaDependencyBlocker {
    pub id: Id,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub idea: Option<IdeaLink>,
    pub message: String,
}

impl IdeaDependencyBlocker {
    pub fn new(id: Id, idea: Option<IdeaLink>) -> Self {
        let message = match &idea {
            Some(l) => format!(
                "Depende de \"{}\" ({}).",
                l.title,
                l.status.label().to_lowercase()
            ),
            None => format!("Depende de uma ideia ausente: {id}."),
        };
        IdeaDependencyBlocker { id, idea, message }
    }
}

/// Detalhe de uma ideia (`ideas show --json`, `get_idea`): campos da ideia + vínculos derivados.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaDetail {
    #[serde(flatten)]
    pub idea: Idea,
    pub slug: String,
    pub dependents: Vec<IdeaLink>,
    pub dependency_blockers: Vec<IdeaDependencyBlocker>,
}

/// Ideia + `slug` e `group` (`GroupedRecord`), para listagens JSON.
#[derive(Debug, Clone, Serialize)]
pub struct GroupedIdea<'a> {
    #[serde(flatten)]
    pub idea: &'a Idea,
    pub slug: &'a str,
    pub group: String,
}

/// Ideia + `slug` (`SlugAnd`), para as respostas de `add_idea`/`update_idea`.
#[derive(Debug, Clone, Serialize)]
pub struct SlugAnd<'a> {
    #[serde(flatten)]
    pub idea: &'a Idea,
    pub slug: &'a str,
}

type IdeaPairs = [(String, Idea)];

/// Toda dependência de `idea` que não está `done` em `ideas`, na ordem. UUID sem ideia correspondente bloqueia.
pub fn dependency_blockers(idea: &Idea, ideas: &IdeaPairs) -> Vec<IdeaDependencyBlocker> {
    let mut by_id: HashMap<Id, &(String, Idea)> = HashMap::new();
    for p in ideas {
        by_id.entry(p.1.id).or_insert(p);
    }
    idea.dependencies
        .iter()
        .filter_map(|id| match by_id.get(id) {
            None => Some(IdeaDependencyBlocker::new(*id, None)),
            Some((slug, found)) => (found.status != IdeaStatus::Done)
                .then(|| IdeaDependencyBlocker::new(*id, Some(IdeaLink::new(slug, found)))),
        })
        .collect()
}

/// Ideias que listam `id` diretamente entre as dependências.
pub fn dependents(id: Id, ideas: &IdeaPairs) -> Vec<IdeaLink> {
    ideas
        .iter()
        .filter(|(_, i)| i.dependencies.contains(&id))
        .map(|(s, i)| IdeaLink::new(s, i))
        .collect()
}

/// Por que `dependencies` não pode ser aplicado à ideia `id`: ela mesma, UUID novo inexistente ou ciclo.
pub fn dependency_problem(id: Id, dependencies: &[Id], ideas: &IdeaPairs) -> Option<String> {
    if dependencies.contains(&id) {
        return Some("uma ideia não pode depender de si mesma.".into());
    }
    let mut graph: HashMap<Id, Vec<Id>> = HashMap::new();
    for (_, i) in ideas {
        graph.entry(i.id).or_insert_with(|| i.dependencies.clone());
    }
    // Vínculo já gravado para ideia removida depois pode ficar (continua bloqueando); novos precisam existir.
    let stored: HashSet<Id> = graph
        .get(&id)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .collect();
    if let Some(missing) = dependencies
        .iter()
        .find(|d| !graph.contains_key(d) && !stored.contains(d))
    {
        return Some(format!("ideia inexistente no projeto: {missing}."));
    }
    graph.insert(id, dependencies.to_vec());
    let mut visited = HashSet::new();
    let mut stack: Vec<Id> = dependencies.to_vec();
    while let Some(next) = stack.pop() {
        if next == id {
            let title = ideas
                .iter()
                .find(|(_, i)| i.id == id)
                .map(|(_, i)| i.title.clone())
                .unwrap_or_else(|| id.to_string());
            return Some(format!(
                "o vínculo criaria um ciclo de dependências passando por \"{title}\"."
            ));
        }
        if !visited.insert(next) {
            continue;
        }
        if let Some(deps) = graph.get(&next) {
            stack.extend(deps.iter().copied());
        }
    }
    None
}

/// Aprovada, com avaliação viável e atual.
pub fn is_eligible(idea: &Idea) -> bool {
    idea.status == IdeaStatus::Approved
        && idea.readiness.as_ref().is_some_and(|r| r.viable)
        && idea
            .readiness
            .as_ref()
            .is_some_and(|r| r.fingerprint == idea.content_fingerprint())
}

/// Por que "Implementar" não está disponível (None = viável).
pub fn implement_blocker(idea: &Idea) -> Option<String> {
    if idea.status.is_closed() {
        return Some(format!("Ideia {}.", idea.status.label().to_lowercase()));
    }
    if idea.rules.is_empty() {
        return Some("Sem regras: rode o Descubra para gerar as regras.".into());
    }
    let Some(readiness) = &idea.readiness else {
        return Some("Ainda não verificada pela IA: rode o Descubra ou Verificar.".into());
    };
    if readiness.fingerprint != idea.content_fingerprint() {
        return Some("A ideia mudou desde a verificação: verifique de novo.".into());
    }
    if !readiness.viable {
        return Some(if readiness.missing.is_empty() {
            "A IA achou a ideia vaga demais para implementar.".into()
        } else {
            format!("Vaga demais. Falta: {}", readiness.missing.join("; "))
        });
    }
    None
}

/// Entrada estável e recuperável de workflows: nem título nem descrição participam da identidade.
pub fn workflow_input(idea: &Idea) -> String {
    format!(
        "Ideia {}. Implemente consultando get_idea pelo UUID; leia a descrição e as regras e siga o tópico promovido, quando houver.",
        idea.id
    )
}

/// Prompt de "Implementar" para uma ideia viável (já promovida, com as regras ativas).
pub fn implementation_prompt(slug: &str, idea: &Idea, topic: Option<&str>) -> String {
    let mut lines = vec![
        format!("Implemente a ideia \"{}\" deste projeto.", idea.title),
        String::new(),
        format!(
            "1. Leia a ideia completa com get_idea (\"{slug}\"): a descrição é a especificação."
        ),
    ];
    lines.push(match topic {
        Some(t) => format!(
            "2. As regras dela já estão ativas no tópico \"{t}\" (get_rule_topic): siga todas."
        ),
        None => "2. Siga as regras rascunho da ideia.".into(),
    });
    lines.extend([
        "3. Antes de implementar: list_stack, list_patterns e os itens de revisão abertos da área."
            .into(),
        "4. Implemente. Se surgir uma decisão que a ideia não cobre, me pergunte antes.".into(),
        "5. Ao terminar: rules_for com os arquivos alterados e submit_rule_check até passed=true."
            .into(),
        "6. Com o check aprovado, marque a ideia como implementada (update_idea status=done)."
            .into(),
    ]);
    lines.join("\n")
}

// ---- globs e arquivos do projeto -----------------------------------------------------------------

const FILE_LIMIT: usize = 20000;
const SKIPPED_DIRS: [&str; 12] = [
    ".git",
    "node_modules",
    ".build",
    "build",
    "DerivedData",
    ".swiftpm",
    "dist",
    ".next",
    "Pods",
    "__pycache__",
    ".venv",
    "target",
];

fn glob_regex(pattern: &str) -> String {
    let mut out = String::from("^");
    let chars: Vec<char> = pattern.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let ch = chars[i];
        i += 1;
        match ch {
            '*' => {
                if chars.get(i) == Some(&'*') {
                    i += 1;
                    if chars.get(i) == Some(&'/') {
                        i += 1;
                        out.push_str("(?:.*/)?");
                    } else {
                        out.push_str(".*");
                    }
                } else {
                    out.push_str("[^/]*");
                }
            }
            '?' => out.push_str("[^/]"),
            '.' | '+' | '(' | ')' | '^' | '$' | '|' | '[' | ']' | '{' | '}' | '\\' => {
                out.push('\\');
                out.push(ch);
            }
            c => out.push(c),
        }
    }
    out.push('$');
    out
}

/// Globs estilo gitignore: `*` (dentro do segmento), `?`, `**` (qualquer profundidade). Sem `/` casa o nome
/// em qualquer profundidade; `/` final casa tudo abaixo.
pub fn glob_matches(pattern: &str, path: &str) -> bool {
    let mut pattern = pattern.trim().to_string();
    if pattern.is_empty() {
        return false;
    }
    if let Some(rest) = pattern.strip_prefix("./") {
        pattern = rest.to_string();
    }
    if let Some(rest) = pattern.strip_prefix('/') {
        pattern = rest.to_string();
    } else if !pattern.contains('/') {
        pattern = format!("**/{pattern}");
    }
    if pattern.ends_with('/') {
        pattern.push_str("**");
    }
    let path = path.strip_prefix("./").unwrap_or(path);
    Regex::new(&format!("(?s){}", glob_regex(&pattern))).is_ok_and(|re| re.is_match(path))
}

/// Arquivos do projeto (relativos), sem ocultos nem saída de build/dependências; até `limit` entradas
/// (pastas contam, com `/` final, e saem do resultado).
pub fn project_files(root: &Path, limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    let walker = walkdir::WalkDir::new(root)
        .min_depth(1)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|e| {
            let name = e.file_name().to_string_lossy();
            e.depth() == 0 || !(name.starts_with('.') || SKIPPED_DIRS.contains(&name.as_ref()))
        });
    let mut seen = 0usize;
    for entry in walker.flatten() {
        seen += 1;
        if !entry.file_type().is_dir()
            && let Ok(rel) = entry.path().strip_prefix(root)
        {
            out.push(rel.to_string_lossy().replace('\\', "/"));
        }
        if seen >= limit {
            break;
        }
    }
    out
}

// ---- casos de uso --------------------------------------------------------------------------------

fn trimmed_non_empty(s: &str) -> Option<String> {
    let t = s.trim();
    (!t.is_empty()).then(|| t.to_string())
}

impl Store {
    /// `(slug, ideia)` de todas as ideias, por `(createdAt, slug)`.
    pub fn idea_pairs(&self) -> crate::Result<Vec<(String, Idea)>> {
        Ok(self
            .ideas()?
            .into_iter()
            .map(|r| (r.slug, r.value))
            .collect())
    }

    /// Cria a ideia (título aparado; `reference` = caminho `grupo/slug`).
    pub fn create_idea(
        &self,
        title: &str,
        body: Option<&str>,
        tags: &[String],
        author: Author,
        reference: Option<&str>,
    ) -> crate::Result<Record<Idea>> {
        let title = trimmed_non_empty(title).ok_or(Error::InvalidName)?;
        let mut idea = Idea::new(title);
        idea.body = body.map(str::to_string);
        idea.tags = tags.to_vec();
        idea.author = author;
        self.ensure_directories()?;
        self.create(&idea, reference)
    }

    /// Resolve, aplica `change`, carimba `updatedAt` e grava.
    pub fn update_idea<F>(&self, reference: &str, change: F) -> IdeaResult<Record<Idea>>
    where
        F: FnOnce(&mut Idea) -> IdeaResult<()>,
    {
        let slug = self.resolve::<Idea>(reference)?;
        let mut idea = self.load::<Idea>(&slug)?;
        change(&mut idea)?;
        idea.updated_at = Timestamp::now();
        self.ensure_directories()?;
        self.save_idea(&slug, &idea)?;
        Ok(Record { slug, value: idea })
    }

    /// Acrescenta uma regra rascunho à ideia.
    pub fn add_idea_rule(&self, reference: &str, rule: Rule) -> IdeaResult<(String, Rule)> {
        let r = rule.clone();
        let rec = self.update_idea(reference, move |i| {
            i.rules.push(rule);
            Ok(())
        })?;
        Ok((rec.slug, r))
    }

    fn release(idea: &mut Idea) {
        idea.promoted_topic = None;
        if idea.status == IdeaStatus::Approved {
            idea.status = IdeaStatus::Exploring;
        }
    }

    /// Transforma as regras rascunho num tópico de regras; promover de novo sincroniza o tópico existente.
    /// Os `paths` da ideia (menos `skipping_paths`) viram os do tópico ou entram nos dele. Devolve o slug.
    pub fn promote_idea(
        &self,
        reference: &str,
        skipping_paths: &HashSet<String>,
    ) -> IdeaResult<String> {
        let idea_slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&idea_slug)?;
        let paths: Vec<String> = idea
            .paths
            .iter()
            .filter(|p| !skipping_paths.contains(*p))
            .cloned()
            .collect();
        let existing = idea
            .promoted_topic
            .as_deref()
            .and_then(|t| self.resolve::<RuleTopic>(t).ok());
        let topic_slug = if let Some(slug) = existing {
            let mut topic = self.load::<RuleTopic>(&slug)?;
            let known: HashSet<Id> = topic.rules.iter().map(|r| r.id).collect();
            topic.rules.extend(
                idea.rules
                    .iter()
                    .filter(|r| !known.contains(&r.id))
                    .cloned(),
            );
            let fresh: Vec<String> = paths
                .iter()
                .filter(|p| !topic.paths.contains(p))
                .cloned()
                .collect();
            topic.paths.extend(fresh);
            self.ensure_directories()?;
            self.save_rule_topic(&slug, &topic)?;
            slug
        } else {
            let title = trimmed_non_empty(&idea.title).ok_or(Error::InvalidName)?;
            let mut topic = RuleTopic::new(title.clone());
            topic.description = Some(format!("Regras vindas da ideia \"{}\".", idea.title));
            topic.paths = paths;
            topic.rules = idea.rules.clone();
            topic.source_idea = Some(idea.id);
            let slug = self.new_slug::<RuleTopic>(&title, None)?;
            self.ensure_directories()?;
            self.save_rule_topic(&slug, &topic)?;
            slug
        };
        let linked = topic_slug.clone();
        self.update_idea(&idea_slug, move |i| {
            i.promoted_topic = Some(linked);
            if !i.status.is_closed() {
                i.status = IdeaStatus::Approved;
            }
            Ok(())
        })?;
        Ok(topic_slug)
    }

    /// Globs da ideia que não casam mais nenhum arquivo do projeto.
    pub fn unmatched_idea_paths(&self, reference: &str) -> crate::Result<Vec<String>> {
        let slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&slug)?;
        if idea.paths.is_empty() {
            return Ok(vec![]);
        }
        let files = project_files(self.root(), FILE_LIMIT);
        Ok(idea
            .paths
            .iter()
            .filter(|g| !files.iter().any(|f| glob_matches(g, f)))
            .cloned()
            .collect())
    }

    /// Desfaz `promote_idea`: apaga o tópico (se ainda existe) e solta a ideia. As regras ficam na ideia.
    /// Devolve o slug do tópico apagado, se houve.
    pub fn unpromote_idea(&self, reference: &str) -> IdeaResult<Option<String>> {
        let idea_slug = self.resolve::<Idea>(reference)?;
        let Some(linked) = self.load::<Idea>(&idea_slug)?.promoted_topic else {
            return Ok(None);
        };
        let topic_slug = self.resolve::<RuleTopic>(&linked).ok();
        if let Some(t) = &topic_slug {
            self.delete_rule_topic(t)?;
        }
        self.update_idea(&idea_slug, |i| {
            Self::release(i);
            Ok(())
        })?;
        Ok(topic_slug)
    }

    /// Solta ideias cujo tópico já não existe. Idempotente; devolve os slugs alterados.
    pub fn release_orphaned_ideas(&self) -> IdeaResult<Vec<String>> {
        let mut released = Vec::new();
        for (slug, idea) in self.idea_pairs()? {
            let Some(linked) = idea.promoted_topic else {
                continue;
            };
            if self.resolve::<RuleTopic>(&linked).is_ok() {
                continue;
            }
            self.update_idea(&slug, |i| {
                Self::release(i);
                Ok(())
            })?;
            released.push(slug);
        }
        Ok(released)
    }

    /// Substitui as dependências (slugs, UUIDs, prefixos ou títulos). Auto-referência, ideia inexistente e ciclo
    /// são recusados antes de gravar; duplicatas colapsam mantendo a primeira.
    pub fn set_idea_dependencies(
        &self,
        reference: &str,
        refs: &[String],
    ) -> IdeaResult<Record<Idea>> {
        let slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&slug)?;
        let ideas = self.idea_pairs()?;
        let mut ids: Vec<Id> = Vec::new();
        for r in refs {
            let direct = Id::from_str(r).ok().filter(|id| {
                *id == idea.id
                    || idea.dependencies.contains(id)
                    || ideas.iter().any(|(_, i)| i.id == *id)
            });
            let id = match direct {
                Some(id) => id,
                None => {
                    let found = self.resolve::<Idea>(r).ok();
                    let target = found.and_then(|f| ideas.iter().find(|(s, _)| *s == f));
                    match target {
                        Some((_, t)) => t.id,
                        None => {
                            return Err(IdeaError::InvalidDependency(format!(
                                "ideia inexistente no projeto: {r}."
                            )));
                        }
                    }
                }
            };
            ids.push(id);
        }
        let mut seen = HashSet::new();
        ids.retain(|i| seen.insert(*i));
        if let Some(problem) = dependency_problem(idea.id, &ids, &ideas) {
            return Err(IdeaError::InvalidDependency(problem));
        }
        if ids == idea.dependencies {
            return Ok(Record { slug, value: idea });
        }
        self.update_idea(&slug, move |i| {
            i.dependencies = ids;
            Ok(())
        })
    }

    pub fn add_idea_dependencies(
        &self,
        reference: &str,
        refs: &[String],
    ) -> IdeaResult<Record<Idea>> {
        let slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&slug)?;
        let mut all: Vec<String> = idea.dependencies.iter().map(Id::to_string).collect();
        all.extend(refs.iter().cloned());
        self.set_idea_dependencies(reference, &all)
    }

    /// Remove os vínculos dados; referências que não são dependências (ou não existem mais) são ignoradas.
    pub fn remove_idea_dependencies(
        &self,
        reference: &str,
        refs: &[String],
    ) -> IdeaResult<Record<Idea>> {
        let slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&slug)?;
        let removed: HashSet<Id> = refs
            .iter()
            .filter_map(|r| {
                Id::from_str(r).ok().or_else(|| {
                    self.resolve::<Idea>(r)
                        .ok()
                        .and_then(|s| self.load::<Idea>(&s).ok())
                        .map(|i| i.id)
                })
            })
            .collect();
        let kept: Vec<String> = idea
            .dependencies
            .iter()
            .filter(|d| !removed.contains(d))
            .map(Id::to_string)
            .collect();
        self.set_idea_dependencies(reference, &kept)
    }

    /// A ideia com os vínculos derivados, lida do disco agora.
    pub fn idea_detail(&self, reference: &str) -> crate::Result<IdeaDetail> {
        let slug = self.resolve::<Idea>(reference)?;
        let idea = self.load::<Idea>(&slug)?;
        let ideas = self.idea_pairs()?;
        Ok(IdeaDetail {
            slug,
            dependents: dependents(idea.id, &ideas),
            dependency_blockers: dependency_blockers(&idea, &ideas),
            idea,
        })
    }

    /// Relê as dependências do disco e falha se alguma ainda estiver pendente.
    pub fn require_idea_dependencies_met(&self, reference: &str) -> IdeaResult<()> {
        let blockers = self.idea_detail(reference)?.dependency_blockers;
        if blockers.is_empty() {
            Ok(())
        } else {
            Err(IdeaError::NotImplementable(
                blockers.into_iter().map(|b| b.message).collect(),
            ))
        }
    }

    /// Porta única para implementar uma ideia: relê ideia e dependências e lista todos os motivos de recusa.
    pub fn implementable_idea(&self, reference: &str) -> IdeaResult<Record<Idea>> {
        let detail = self.idea_detail(reference)?;
        let mut reasons = Vec::new();
        if !is_eligible(&detail.idea) {
            reasons.push(
                "a ideia precisa estar aprovada e ter uma avaliação viável atual. Verifique novamente."
                    .to_string(),
            );
        }
        reasons.extend(detail.dependency_blockers.iter().map(|b| b.message.clone()));
        if !reasons.is_empty() {
            return Err(IdeaError::NotImplementable(reasons));
        }
        Ok(Record {
            slug: detail.slug,
            value: detail.idea,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn group_path_like_swift() {
        assert_eq!(group_path("a/b/x"), "a/b");
        assert_eq!(group_path("x"), "");
        assert_eq!(group_path(""), "");
    }

    #[test]
    fn glob_cases() {
        assert!(glob_matches("Sources/App/**", "Sources/App/View.swift"));
        assert!(!glob_matches("Sources/Gone/**", "Sources/App/View.swift"));
        assert!(glob_matches("*.rs", "a/b/c.rs"));
        assert!(glob_matches("docs/", "docs/x/y.md"));
        assert!(glob_matches("/Package.swift", "Package.swift"));
        assert!(glob_matches("**/x.rs", "x.rs"));
        assert!(!glob_matches("", "x"));
        assert!(!glob_matches("a?c", "a/c"));
    }

    #[test]
    fn fingerprint_is_16_hex_and_ignores_status() {
        let mut i = Idea::new("T");
        let f = i.content_fingerprint();
        assert_eq!(f.len(), 16);
        i.status = IdeaStatus::Approved;
        i.tags = vec!["x".into()];
        i.dependencies = vec![Id::new()];
        assert_eq!(i.content_fingerprint(), f);
        i.body = Some("b".into());
        assert_ne!(i.content_fingerprint(), f);
    }
}
