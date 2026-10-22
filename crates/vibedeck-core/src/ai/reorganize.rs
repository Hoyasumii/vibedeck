//! Reorganização com IA (ReorganizeDiscover.swift): prompt, validação da resposta, análise com provider
//! somente leitura e aplicação com aceite explícito.
//!
//! Montar o prompt, validar a resposta e analisar nunca gravam. `apply` é o único ponto que escreve: todas as
//! ações aceitas são preparadas em memória sobre os bytes dos arquivos e só então confirmadas, de forma
//! atômica e reversível (`Receipt` guarda antes/depois).

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use regex::Regex;
use serde::{Deserialize, Serialize, Serializer};
use serde_json::{Map, Value};

use super::codex;
use super::process::{self, DISCOVER_TIMEOUT};
use super::{AiError, Provider, Result, sha256_hex};
use crate::json;
use crate::model::{Author, Idea, RuleTopic};
use crate::paths;
use crate::slug;
use crate::store::{PROJECT_FILE, Store, write_atomic};

pub use crate::model::ProviderSettings;

pub const SCHEMA: &str = include_str!("reorganize_schema.json");
const PROMPT_HEAD: &str = include_str!("reorganize_prompt.txt");
pub const TIMEOUT: Duration = DISCOVER_TIMEOUT;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Concept {
    Rules,
    Docs,
    Ideas,
    Reviews,
}

impl Concept {
    pub const ALL: [Concept; 4] = [
        Concept::Rules,
        Concept::Docs,
        Concept::Ideas,
        Concept::Reviews,
    ];

    pub fn raw(self) -> &'static str {
        match self {
            Concept::Rules => "rules",
            Concept::Docs => "docs",
            Concept::Ideas => "ideas",
            Concept::Reviews => "reviews",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Conflict,
    Merge,
    Move,
    Create,
    Flow,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Reference {
    pub concept: Concept,
    pub slug: String,
    #[serde(default, rename = "itemID", skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
}

impl Reference {
    pub fn new(concept: Concept, slug: &str) -> Self {
        Reference {
            concept,
            slug: slug.to_string(),
            item_id: None,
        }
    }

    pub fn with_item(concept: Concept, slug: &str, item_id: &str) -> Self {
        Reference {
            item_id: Some(item_id.to_string()),
            ..Reference::new(concept, slug)
        }
    }

    /// `rules/topico#<itemID>`.
    pub fn key(&self) -> String {
        format!(
            "{}/{}{}",
            self.concept.raw(),
            self.slug,
            self.item_id
                .as_ref()
                .map(|i| format!("#{i}"))
                .unwrap_or_default()
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Action {
    pub id: String,
    pub kind: Kind,
    pub item: Reference,
    pub involved: Vec<Reference>,
    pub reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
}

impl Action {
    pub fn new(kind: Kind, item: Reference, reason: &str) -> Self {
        Action {
            id: crate::model::Id::new().to_string(),
            kind,
            item,
            involved: vec![],
            reason: reason.to_string(),
            destination: None,
            title: None,
            content: None,
        }
    }

    /// `[item] + involved` sem repetir `item`.
    pub fn references(&self) -> Vec<Reference> {
        let mut all = vec![self.item.clone()];
        all.extend(self.involved.iter().filter(|r| **r != self.item).cloned());
        all
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Answer {
    pub actions: Vec<Action>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Proposal {
    pub fingerprint: String,
    pub actions: Vec<Action>,
    pub discarded: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Acceptance {
    pub selected: Vec<String>,
    /// Id da ação → chave do item existente escolhido para ficar.
    pub conflicts: BTreeMap<String, String>,
}

pub fn decode_proposal(data: &[u8]) -> Result<Proposal> {
    serde_json::from_slice(data).map_err(|_| AiError::ReorganizeInvalidJson)
}

pub fn decode_acceptance(data: &[u8]) -> Result<Acceptance> {
    serde_json::from_slice(data).map_err(|_| AiError::ReorganizeInvalidJson)
}

#[derive(Debug, Clone, Serialize)]
pub struct CatalogItem {
    pub reference: Reference,
    pub title: String,
}

// Recibo: bytes em base64, como o `Data` do JSONEncoder.
fn base64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        out.push(T[(n >> 18) as usize & 63] as char);
        out.push(T[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            T[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            T[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

fn ser_bytes_map<S: Serializer>(
    map: &BTreeMap<String, Vec<u8>>,
    s: S,
) -> std::result::Result<S::Ok, S::Error> {
    s.collect_map(map.iter().map(|(k, v)| (k, base64(v))))
}

/// Decodifica base64 padrão (com `=`), o formato do `Data` do JSONEncoder do Swift.
pub fn decode_base64(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() / 4 * 3);
    let mut acc = 0u32;
    let mut bits = 0u32;
    let mut padding = 0usize;
    for c in text.bytes().filter(|c| !c.is_ascii_whitespace()) {
        let value = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => {
                padding += 1;
                continue;
            }
            _ => return None,
        };
        if padding > 0 {
            return None;
        }
        acc = (acc << 6) | u32::from(value);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    (padding <= 2 && acc == 0).then_some(out)
}

fn de_bytes_map<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> std::result::Result<BTreeMap<String, Vec<u8>>, D::Error> {
    let raw = BTreeMap::<String, String>::deserialize(d)?;
    raw.into_iter()
        .map(|(k, v)| {
            decode_base64(&v)
                .map(|bytes| (k, bytes))
                .ok_or_else(|| serde::de::Error::custom("bytes do recibo não são base64 válido"))
        })
        .collect()
}

/// Recibo de `apply`. No JSON, `before`/`after` mapeiam caminho -> bytes em base64 padrão (com `=`), a
/// codificação do `Data` do Swift (`JSONEncoder` padrão), nos dois sentidos.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Receipt {
    #[serde(serialize_with = "ser_bytes_map", deserialize_with = "de_bytes_map")]
    pub before: BTreeMap<String, Vec<u8>>,
    #[serde(serialize_with = "ser_bytes_map", deserialize_with = "de_bytes_map")]
    pub after: BTreeMap<String, Vec<u8>>,
    #[serde(default)]
    pub created_directories: Vec<String>,
    #[serde(default)]
    pub path_moves: BTreeMap<String, String>,
}

type Files = BTreeMap<String, Vec<u8>>;

// ---- Markdown mínimo (Markdown.title/tags/settingTags) ---------------------------------------------

fn trim_ws(s: &str) -> &str {
    s.trim_matches([' ', '\t'])
}

fn frontmatter(text: &str) -> (Option<Vec<&str>>, Vec<&str>) {
    let lines: Vec<&str> = text.split('\n').collect();
    if lines.first().is_some_and(|l| trim_ws(l) == "---")
        && let Some(end) = lines[1..].iter().position(|l| trim_ws(l) == "---")
    {
        let end = end + 1;
        return (Some(lines[1..end].to_vec()), lines[end + 1..].to_vec());
    }
    (None, lines)
}

pub fn markdown_title(text: &str) -> Option<String> {
    let (front, body) = frontmatter(text);
    if let Some(line) = front
        .as_ref()
        .and_then(|f| f.iter().find(|l| l.starts_with("title:")))
    {
        let value = line["title:".len()..].trim_matches([' ', '"', '\'']);
        if !value.is_empty() {
            return Some(value.to_string());
        }
    }
    body.iter().find(|l| l.starts_with("# ")).and_then(|l| {
        Some(trim_ws(&l[2..]))
            .filter(|v| !v.is_empty())
            .map(str::to_string)
    })
}

pub fn markdown_tags(text: &str) -> Vec<String> {
    let (front, _) = frontmatter(text);
    let Some(line) = front.and_then(|f| f.into_iter().find(|l| l.starts_with("tags:"))) else {
        return vec![];
    };
    line["tags:".len()..]
        .trim_matches([' ', '[', ']'])
        .split(',')
        .map(|t| t.trim_matches([' ', '"', '\'']).to_string())
        .filter(|t| !t.is_empty())
        .collect()
}

pub fn markdown_setting_tags(tags: &[String], text: &str) -> String {
    let tag_line = (!tags.is_empty()).then(|| format!("tags: [{}]", tags.join(", ")));
    let (front, body) = frontmatter(text);
    let mut lines: Vec<String> = front
        .unwrap_or_default()
        .into_iter()
        .filter(|l| !l.starts_with("tags:"))
        .map(str::to_string)
        .collect();
    if let Some(t) = tag_line {
        lines.push(t);
    }
    let body_text = body.join("\n");
    if lines.is_empty() {
        return body_text;
    }
    let mut all = vec!["---".to_string()];
    all.extend(lines);
    all.push("---".into());
    format!("{}\n{body_text}", all.join("\n"))
}

/// Aproximação de `localizedStandardCompare`: sem caixa/acento e com números por valor.
fn standard_compare(a: &str, b: &str) -> std::cmp::Ordering {
    fn chunks(s: &str) -> Vec<(bool, String)> {
        let mut out: Vec<(bool, String)> = Vec::new();
        for c in slug::fold(s).chars() {
            let digit = c.is_ascii_digit();
            match out.last_mut() {
                Some((d, text)) if *d == digit => text.push(c),
                _ => out.push((digit, c.to_string())),
            }
        }
        out
    }
    let (ca, cb) = (chunks(a), chunks(b));
    for (x, y) in ca.iter().zip(cb.iter()) {
        let ord = if x.0 && y.0 {
            let (nx, ny) = (x.1.trim_start_matches('0'), y.1.trim_start_matches('0'));
            nx.len().cmp(&ny.len()).then_with(|| nx.cmp(ny))
        } else {
            x.1.cmp(&y.1)
        };
        if ord != std::cmp::Ordering::Equal {
            return ord;
        }
    }
    ca.len().cmp(&cb.len()).then_with(|| a.cmp(b))
}

// ---- arquivos --------------------------------------------------------------------------------------

fn vdjson(value: &Value) -> Vec<u8> {
    json::to_vdjson(value).into_bytes()
}

fn io_err(path: &Path, e: std::io::Error) -> AiError {
    AiError::io(path, e)
}

/// `recordFiles`: arquivos regulares `*.<ext>` (extensão em minúsculas), sem ocultos nem symlinks, contidos
/// na pasta; caminhos canônicos ordenados.
fn record_files(store: &Store, dir: &Path, ext: &str) -> Result<Vec<PathBuf>> {
    if !dir.exists() {
        return Ok(vec![]);
    }
    let data = store.data_dir();
    let mut files = Vec::new();
    let walker = walkdir::WalkDir::new(dir)
        .min_depth(1)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| !e.file_name().to_string_lossy().starts_with('.'));
    for entry in walker.flatten() {
        let ft = entry.file_type();
        if ft.is_symlink() || !ft.is_file() {
            continue;
        }
        if entry
            .path()
            .extension()
            .is_some_and(|e| e.to_string_lossy().to_lowercase() == ext)
        {
            let rel = paths::relative_to(dir, entry.path(), false).unwrap_or_default();
            paths::contained(&data, dir, &rel)?;
            files.push(paths::canonical(entry.path()));
        }
    }
    files.sort();
    Ok(files)
}

fn concept_dir(store: &Store, name: &str) -> PathBuf {
    store.data_dir().join(name)
}

struct Doc {
    slug: String,
    title: String,
}

fn list_docs(store: &Store) -> Result<Vec<Doc>> {
    let dir = concept_dir(store, "docs");
    let mut docs = Vec::new();
    for file in record_files(store, &dir, "md")? {
        let Some(slug) = paths::relative_to(&dir, &file, true) else {
            continue;
        };
        let text = fs::read_to_string(&file).unwrap_or_default();
        docs.push(Doc {
            title: markdown_title(&text).unwrap_or_else(|| slug.clone()),
            slug,
        });
    }
    docs.sort_by(|a, b| standard_compare(&a.title, &b.title));
    Ok(docs)
}

fn resolve_doc(store: &Store, reference: &str) -> Option<String> {
    let docs = list_docs(store).ok()?;
    let candidates: Vec<slug::Candidate> = docs
        .iter()
        .map(|d| slug::Candidate {
            slug: d.slug.clone(),
            id: crate::model::Id(uuid::Uuid::nil()),
            title: d.title.clone(),
        })
        .collect();
    let dir = concept_dir(store, "docs");
    slug::resolve(reference, &candidates, |r| {
        paths::normalize_group_path(r, false)?;
        Ok(paths::contained(&store.data_dir(), &dir, &format!("{r}.md"))?.exists())
    })
    .ok()
    .flatten()
}

/// Referências do catálogo: tópicos, docs, ideias, grupos de revisão e os itens de cada grupo.
pub fn catalog(store: &Store) -> Result<Vec<CatalogItem>> {
    let mut out: Vec<CatalogItem> = store
        .rule_topics()?
        .into_iter()
        .map(|r| CatalogItem {
            reference: Reference::new(Concept::Rules, &r.slug),
            title: r.value.title,
        })
        .collect();
    out.extend(list_docs(store)?.into_iter().map(|d| CatalogItem {
        reference: Reference::new(Concept::Docs, &d.slug),
        title: d.title,
    }));
    out.extend(store.ideas()?.into_iter().map(|r| CatalogItem {
        reference: Reference::new(Concept::Ideas, &r.slug),
        title: r.value.title,
    }));
    for group in store.review_groups()? {
        out.push(CatalogItem {
            reference: Reference::new(Concept::Reviews, &group.slug),
            title: group.value.title.clone(),
        });
        for item in &group.value.items {
            out.push(CatalogItem {
                reference: Reference::with_item(
                    Concept::Reviews,
                    &group.slug,
                    &item.id.to_string(),
                ),
                title: item.title.clone(),
            });
        }
    }
    Ok(out)
}

/// Não inclui checks, scripts gerados, logs nem o conteúdo de `archive/`.
fn reorganize_bytes(store: &Store) -> Result<Files> {
    let mut result = Files::new();
    for name in [
        "rules",
        "docs",
        "ideas",
        "reviews",
        "agents",
        "commands",
        "skills",
        "workflows",
    ] {
        let dir = concept_dir(store, name);
        for ext in ["json", "md"] {
            for url in record_files(store, &dir, ext)? {
                let rel = paths::relative_to(&dir, &url, false).unwrap_or_default();
                let data = fs::read(&url).map_err(|e| io_err(&url, e))?;
                result.insert(format!(".vibedeck/{name}/{rel}"), data);
            }
        }
    }
    let manifest = store.root().join(PROJECT_FILE);
    if manifest.exists() {
        result.insert(
            PROJECT_FILE.to_string(),
            fs::read(&manifest).map_err(|e| io_err(&manifest, e))?,
        );
    }
    Ok(result)
}

/// SHA-256 dos arquivos reorganizáveis (nome, tamanho e bytes) e das pastas dos quatro conceitos.
pub fn fingerprint(store: &Store) -> Result<String> {
    let bytes = reorganize_bytes(store)?;
    let mut data: Vec<u8> = Vec::new();
    for (key, value) in &bytes {
        data.extend_from_slice(key.as_bytes());
        data.push(0);
        data.extend_from_slice(value.len().to_string().as_bytes());
        data.push(0);
        data.extend_from_slice(value);
    }
    let mut directories: Vec<String> = Vec::new();
    for concept in Concept::ALL {
        let dir = concept_dir(store, concept.raw());
        if !dir.exists() {
            continue;
        }
        let walker = walkdir::WalkDir::new(&dir)
            .min_depth(1)
            .follow_links(false)
            .into_iter()
            .filter_entry(|e| !e.file_name().to_string_lossy().starts_with('.'));
        for entry in walker.flatten() {
            if entry.file_type().is_dir() {
                let rel = paths::relative_to(&dir, entry.path(), false).unwrap_or_default();
                directories.push(format!("{}/{rel}/", concept.raw()));
            }
        }
    }
    directories.sort();
    for d in directories {
        data.extend_from_slice(d.as_bytes());
        data.push(0);
    }
    Ok(sha256_hex(&data))
}

// ---- prompt e validação ----------------------------------------------------------------------------

pub fn prompt(store: &Store) -> Result<String> {
    let cat = json::encode(&catalog(store)?).map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
    Ok(format!("{PROMPT_HEAD}{}", String::from_utf8_lossy(&cat)))
}

const ACTION_KEYS: [&str; 8] = [
    "id",
    "kind",
    "item",
    "involved",
    "reason",
    "destination",
    "title",
    "content",
];

/// Resposta JSON da IA → proposta validada. Ações inválidas são descartadas (e contadas).
pub fn parse(data: &[u8], store: &Store, fingerprint_expected: &str) -> Result<Proposal> {
    let invalid = || AiError::ReorganizeInvalidJson;
    let raw: Value = serde_json::from_slice(data).map_err(|_| invalid())?;
    let obj = raw.as_object().ok_or_else(invalid)?;
    if obj.len() != 1 || !obj.contains_key("actions") {
        return Err(invalid());
    }
    let raw_actions = obj["actions"].as_array().ok_or_else(invalid)?;
    let shape_ok = raw_actions.iter().all(|a| {
        a.as_object()
            .is_some_and(|o| o.keys().all(|k| ACTION_KEYS.contains(&k.as_str())))
    });
    if !shape_ok {
        return Err(invalid());
    }
    if data.len() > 2_000_000 {
        return Err(invalid());
    }
    let answer: Answer = serde_json::from_slice(data).map_err(|_| invalid())?;
    if answer.actions.len() > 100 {
        return Err(invalid());
    }
    if fingerprint(store)? != fingerprint_expected {
        return Err(AiError::ReorganizeStale);
    }
    let known: HashSet<Reference> = catalog(store)?.into_iter().map(|c| c.reference).collect();
    let mut ids = HashSet::new();
    let mut valid = Vec::new();
    for action in &answer.actions {
        if is_valid(action, &known, &mut ids) {
            valid.push(action.clone());
        }
    }
    let discarded = (answer.actions.len() - valid.len()) as i64;
    Ok(Proposal {
        fingerprint: fingerprint_expected.to_string(),
        actions: valid,
        discarded,
    })
}

fn is_valid(action: &Action, known: &HashSet<Reference>, ids: &mut HashSet<String>) -> bool {
    let refs = action.references();
    let blank = |s: &Option<String>| s.as_deref().is_none_or(|t| t.trim().is_empty());
    if action.id.is_empty()
        || !ids.insert(action.id.clone())
        || action.reason.trim().is_empty()
        || super::graphemes::count(&action.reason) > 2000
        || !refs.iter().all(|r| known.contains(r))
        || refs.iter().collect::<HashSet<_>>().len() != refs.len()
    {
        return false;
    }
    if let Some(path) = &action.destination
        && paths::normalize_group_path(path, true).is_err()
    {
        return false;
    }
    match action.kind {
        Kind::Conflict | Kind::Merge => {
            refs.len() >= 2 && refs.iter().all(|r| r.concept == action.item.concept)
        }
        Kind::Move => action.destination.is_some() && action.item.item_id.is_none(),
        Kind::Create => action.destination.is_some() && !blank(&action.title),
        Kind::Flow => {
            !blank(&action.title)
                && !blank(&action.content)
                && action.content.as_deref().map_or(0, super::graphemes::count) <= 40_000
        }
    }
}

// ---- análise com provider ---------------------------------------------------------------------------

/// Trava por projeto (`flock` na raiz): uma análise por vez.
pub struct Lease {
    _file: fs::File,
}

impl Lease {
    pub fn acquire(root: &Path) -> Result<Lease> {
        use std::os::fd::AsRawFd;
        let key = fs::canonicalize(root).map_err(|_| AiError::ReorganizeInvalidAction)?;
        let file = fs::File::open(&key).map_err(|_| AiError::ReorganizeInvalidAction)?;
        // SAFETY: fd válido e próprio; LOCK_NB nunca bloqueia. O lock cai quando o arquivo é fechado.
        let locked = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if locked != 0 {
            return Err(AiError::ReorganizeBusy);
        }
        Ok(Lease { _file: file })
    }
}

/// Extrai a resposta do envelope `claude -p --output-format json` (linha com `type: result`).
fn claude_reply(envelope: &[u8]) -> Result<Vec<u8>> {
    let text = String::from_utf8_lossy(envelope);
    let find = |v: &Value| v.get("type").and_then(Value::as_str) == Some("result");
    let result = text
        .lines()
        .rev()
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .find(find)
        .or_else(|| serde_json::from_str::<Value>(text.trim()).ok().filter(find))
        .ok_or(AiError::ReorganizeInvalidJson)?;
    if result.get("is_error").and_then(Value::as_bool) == Some(true)
        || result.get("subtype").and_then(Value::as_str) != Some("success")
    {
        return Err(AiError::ReorganizeInvalidJson);
    }
    match result.get("structured_output") {
        Some(v) if !v.is_null() => Ok(vdjson(v)),
        _ => Ok(result
            .get("result")
            .and_then(Value::as_str)
            .unwrap_or("")
            .as_bytes()
            .to_vec()),
    }
}

/// Analisa com `claude` ou `codex` somente leitura e devolve a proposta validada.
pub fn analyze(store: &Store, provider: Provider, settings: &ProviderSettings) -> Result<Proposal> {
    let _lease = Lease::acquire(store.root())?;
    let fp = fingerprint(store)?;
    let prompt_text = prompt(store)?;
    let reply: Vec<u8> = match provider {
        Provider::Codex => {
            let schema: Value =
                serde_json::from_str(SCHEMA).map_err(|_| AiError::CodexInvalidResponse)?;
            codex::run_read_only(store.root(), &prompt_text, &schema, TIMEOUT, settings)?
                .text
                .into_bytes()
        }
        Provider::Claude => {
            let exe = Provider::Claude
                .executable()
                .ok_or(AiError::Unavailable(Provider::Claude))?;
            let envelope = process::run_claude_read_only(
                &exe,
                store.root(),
                &prompt_text,
                SCHEMA,
                settings,
                TIMEOUT,
            )?;
            claude_reply(&envelope)?
        }
    };
    parse(&reply, store, &fp)
}

// ---- aplicação -------------------------------------------------------------------------------------

fn reorganize_path(r: &Reference) -> String {
    format!(
        ".vibedeck/{}/{}{}",
        r.concept.raw(),
        r.slug,
        if r.concept == Concept::Docs {
            ".md"
        } else {
            ".json"
        }
    )
}

fn real_root(store: &Store) -> PathBuf {
    fs::canonicalize(store.root()).unwrap_or_else(|_| store.root().to_path_buf())
}

/// Caminho absoluto de uma chave do recibo; só pastas de conceitos reorganizáveis e `vibedeck.json`.
fn reorganize_url(store: &Store, path: &str) -> Result<PathBuf> {
    let root = real_root(store);
    if path == PROJECT_FILE {
        let manifest = store.root().join(PROJECT_FILE);
        if paths::canonical(&manifest) != root.join(PROJECT_FILE) {
            return Err(AiError::ReorganizeInvalidAction);
        }
        return Ok(manifest);
    }
    if !path.starts_with(".vibedeck/")
        || path.starts_with(".vibedeck/checks/")
        || path.starts_with(".vibedeck/tests/")
    {
        return Err(AiError::ReorganizeInvalidAction);
    }
    let relative = &path[".vibedeck/".len()..];
    let allowed = [
        "rules",
        "docs",
        "ideas",
        "reviews",
        "agents",
        "commands",
        "skills",
        "workflows",
        "archive",
    ];
    let top = relative.split('/').next().unwrap_or("");
    if !allowed.contains(&top) {
        return Err(AiError::ReorganizeInvalidAction);
    }
    paths::normalize_group_path(relative, false)?;
    let target = paths::canonical(&store.data_dir().join(relative));
    let base = root.join(".vibedeck").join(top);
    if target != base && !target.starts_with(&base) {
        return Err(AiError::ReorganizeInvalidAction);
    }
    Ok(target)
}

fn read_value(files: &Files, key: &str) -> Option<Value> {
    serde_json::from_slice(files.get(key)?).ok()
}

fn object(r: &Reference, files: &Files) -> Result<Map<String, Value>> {
    let Some(Value::Object(obj)) = read_value(files, &reorganize_path(r)) else {
        return Err(AiError::ReorganizeInvalidAction);
    };
    if let Some(id) = &r.item_id {
        return obj
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| {
                items
                    .iter()
                    .find(|i| i.get("id").and_then(Value::as_str) == Some(id))
            })
            .and_then(|i| i.as_object().cloned())
            .ok_or(AiError::ReorganizeInvalidAction);
    }
    Ok(obj)
}

fn save_object(obj: Map<String, Value>, r: &Reference, files: &mut Files) -> Result<()> {
    let path = reorganize_path(r);
    if let Some(id) = &r.item_id {
        let mut group = object(&Reference::new(Concept::Reviews, &r.slug), files)?;
        let mut items = group
            .get("items")
            .and_then(Value::as_array)
            .cloned()
            .ok_or(AiError::ReorganizeInvalidAction)?;
        let index = items
            .iter()
            .position(|i| i.get("id").and_then(Value::as_str) == Some(id))
            .ok_or(AiError::ReorganizeInvalidAction)?;
        items[index] = Value::Object(obj);
        group.insert("items".into(), Value::Array(items));
        files.insert(path, vdjson(&Value::Object(group)));
    } else {
        files.insert(path, vdjson(&Value::Object(obj)));
    }
    Ok(())
}

fn is_closed(item: &Value) -> bool {
    matches!(
        item.get("status").and_then(Value::as_str),
        Some("done" | "wontfix")
    )
}

fn protected(store: &Store, r: &Reference, files: &Files) -> Result<bool> {
    if r.concept == Concept::Docs {
        return Ok(false);
    }
    let item = object(r, files)?;
    Ok(match r.concept {
        Concept::Ideas => item.contains_key("promotedTopic"),
        Concept::Rules => {
            if item.contains_key("sourceIdea") || item.contains_key("sourcePattern") {
                return Ok(true);
            }
            store.ideas()?.iter().any(|idea| {
                idea.value.promoted_topic.as_deref().is_some_and(|linked| {
                    store.resolve::<RuleTopic>(linked).ok().as_deref() == Some(r.slug.as_str())
                })
            })
        }
        Concept::Reviews => {
            if r.item_id.is_some() {
                is_closed(&Value::Object(item))
            } else {
                item.get("items")
                    .and_then(Value::as_array)
                    .is_some_and(|items| items.iter().any(is_closed))
            }
        }
        Concept::Docs => false,
    })
}

fn unique_slug(store: &Store, base: &str, concept: Concept, files: &Files) -> String {
    let dir = concept_dir(store, concept.raw());
    let ext = if concept == Concept::Docs {
        "md"
    } else {
        "json"
    };
    let mut slug = slug::unique(base, &dir, ext);
    let mut n = 2;
    while files.contains_key(&reorganize_path(&Reference::new(concept, &slug))) {
        slug = format!("{base}-{n}");
        n += 1;
    }
    slug
}

fn merge(keeper: &Reference, removed: &Reference, files: &mut Files) -> Result<()> {
    if keeper.concept == Concept::Docs {
        let text = |r: &Reference| {
            String::from_utf8_lossy(files.get(&reorganize_path(r)).map_or(&[][..], |v| v))
                .into_owned()
        };
        let (left, right) = (text(keeper), text(removed));
        let tags: BTreeSet<String> = markdown_tags(&left)
            .into_iter()
            .chain(markdown_tags(&right))
            .collect();
        let tags: Vec<String> = tags.into_iter().collect();
        files.insert(
            reorganize_path(keeper),
            markdown_setting_tags(&tags, &format!("{left}\n\n{right}")).into_bytes(),
        );
        return Ok(());
    }
    let mut left = object(keeper, files)?;
    let right = object(removed, files)?;
    let strs_empty = |m: &Map<String, Value>| {
        m.get("paths")
            .and_then(Value::as_array)
            .is_none_or(Vec::is_empty)
    };
    if keeper.concept == Concept::Rules && strs_empty(&left) != strs_empty(&right) {
        return Err(AiError::ReorganizeIncompatible);
    }
    const UNION: [&str; 4] = ["tags", "paths", "rules", "items"];
    const TEXT: [&str; 3] = ["body", "description", "details"];
    const IDENTITY: [&str; 6] = ["id", "title", "$schema", "author", "createdAt", "updatedAt"];
    for (key, value) in &right {
        if UNION.contains(&key.as_str()) {
            let mut union: Vec<Value> = left
                .get(key)
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            for entry in value.as_array().cloned().unwrap_or_default() {
                let same = entry.get("id").and_then(Value::as_str).and_then(|id| {
                    union
                        .iter()
                        .find(|u| u.get("id").and_then(Value::as_str) == Some(id))
                });
                if entry.is_object()
                    && entry.get("id").is_some_and(Value::is_string)
                    && same.is_some()
                {
                    if same != Some(&entry) {
                        return Err(AiError::ReorganizeIncompatible);
                    }
                } else if !union.contains(&entry) {
                    union.push(entry);
                }
            }
            left.insert(key.clone(), Value::Array(union));
        } else if TEXT.contains(&key.as_str()) && value.is_string() {
            let content = value.as_str().unwrap_or("");
            let current = left
                .get(key)
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let merged = if current == content || content.is_empty() {
                current
            } else if current.is_empty() {
                content.to_string()
            } else {
                format!("{current}\n\n{content}")
            };
            left.insert(key.clone(), Value::String(merged));
        } else if !IDENTITY.contains(&key.as_str()) {
            match left.get(key) {
                Some(current) => {
                    if current != value {
                        return Err(AiError::ReorganizeIncompatible);
                    }
                }
                None => {
                    left.insert(key.clone(), value.clone());
                }
            }
        }
    }
    save_object(left, keeper, files)
}

fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

fn components(p: &Path) -> Vec<String> {
    p.components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect()
}

/// Reescreve só campos de referência e destinos de links; prosa e checks ficam intactos.
struct Rewriter<'a> {
    store: &'a Store,
    old: &'a Reference,
    new: &'a Reference,
    old_file: String,
    new_file: String,
    identity: Option<String>,
    link_re: Regex,
}

impl<'a> Rewriter<'a> {
    fn new(store: &'a Store, old: &'a Reference, new: &'a Reference) -> Self {
        let old_file = reorganize_path(old);
        let disk = reorganize_url(store, &old_file)
            .ok()
            .and_then(|p| fs::read(p).ok())
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok());
        let identity = old.item_id.clone().or_else(|| {
            disk.as_ref()
                .and_then(|v| v.get("id"))
                .and_then(Value::as_str)
                .map(str::to_string)
        });
        Rewriter {
            store,
            old,
            new,
            old_file,
            new_file: reorganize_path(new),
            identity,
            link_re: Regex::new(r"\]\(([^\s)]+)|\]: ([^\s]+)").expect("regex fixa"),
        }
    }

    fn identifies(&self, reference: &str) -> bool {
        if let Some(id) = &self.old.item_id {
            return reference.to_lowercase() == id.to_lowercase();
        }
        let resolved: Option<String> = match self.old.concept {
            Concept::Rules => self.store.resolve::<RuleTopic>(reference).ok(),
            Concept::Ideas => self.store.resolve::<Idea>(reference).ok(),
            Concept::Reviews => self
                .store
                .resolve::<crate::model::ReviewGroup>(reference)
                .ok(),
            Concept::Docs => resolve_doc(self.store, reference),
        };
        resolved.as_deref() == Some(self.old.slug.as_str())
            || reference == self.old.slug
            || self.identity.as_deref() == Some(reference)
    }

    fn destination(&self, text: &str, owner: &str, moved_owner: bool) -> String {
        if text.is_empty()
            || text.starts_with('#')
            || text.contains("://")
            || text.starts_with("mailto:")
            || text.starts_with("data:")
        {
            return text.to_string();
        }
        let split = text.find(['#', '?']).unwrap_or(text.len());
        let (path, suffix) = (&text[..split], &text[split..]);
        let owner_path = if owner == self.new_file && moved_owner {
            &self.old_file
        } else {
            owner
        };
        let root = self.store.root();
        let base = root.join(owner_path);
        let base = base.parent().unwrap_or(root).to_path_buf();
        let decoded = percent_decode(path).unwrap_or_else(|| path.to_string());
        let resolved = if decoded.starts_with('/') {
            paths::lexical_normalize(Path::new(&decoded))
        } else {
            paths::lexical_normalize(&base.join(&decoded))
        };
        let source = paths::lexical_normalize(&root.join(&self.old_file));
        let target = if resolved == source {
            root.join(&self.new_file)
        } else if moved_owner {
            resolved
        } else {
            return text.to_string();
        };
        let target = paths::lexical_normalize(&target);
        if path.starts_with('/') {
            return format!("{}{suffix}", target.to_string_lossy());
        }
        let output_base = paths::lexical_normalize(root.join(owner).parent().unwrap_or(root));
        let (ob, tp) = (components(&output_base), components(&target));
        let mut shared = 0;
        while shared < ob.len().min(tp.len()) && ob[shared] == tp[shared] {
            shared += 1;
        }
        let mut parts: Vec<String> = vec!["..".to_string(); ob.len() - shared];
        parts.extend(tp[shared..].iter().cloned());
        format!("{}{suffix}", parts.join("/"))
    }

    fn markdown(&self, text: &str, owner: &str, moved_owner: bool) -> String {
        let mut result = String::with_capacity(text.len());
        let mut last = 0;
        for caps in self.link_re.captures_iter(text) {
            let m = caps
                .get(1)
                .or_else(|| caps.get(2))
                .expect("um dos grupos casa");
            result.push_str(&text[last..m.start()]);
            result.push_str(&self.destination(m.as_str(), owner, moved_owner));
            last = m.end();
        }
        result.push_str(&text[last..]);
        result
    }

    fn rewrite(&self, value: &Value, owner: &str) -> Value {
        match value {
            Value::Array(list) => {
                Value::Array(list.iter().map(|v| self.rewrite(v, owner)).collect())
            }
            Value::Object(map) => {
                let mut record = map.clone();
                let raw = self.old.concept.raw();
                let singular = &raw[..raw.len() - 1];
                if let (Some(r), Some(kind)) = (
                    record.get("ref").and_then(Value::as_str),
                    record.get("kind").and_then(Value::as_str),
                ) && (kind == raw
                    || kind == singular
                    || (self.old.concept == Concept::Rules && kind == "topic"))
                    && self.identifies(r)
                {
                    let replacement = match &self.old.item_id {
                        None => Value::String(self.new.slug.clone()),
                        Some(_) => self.new.item_id.clone().map_or(Value::Null, Value::String),
                    };
                    record.insert("ref".into(), replacement);
                }
                if let Some(r) = record.get("ref").and_then(Value::as_str) {
                    let moved = self.destination(r, PROJECT_FILE, false);
                    record.insert("ref".into(), Value::String(moved));
                }
                if self.old.concept == Concept::Rules {
                    if let Some(refs) = record.get("rules").and_then(Value::as_array)
                        && refs.iter().all(Value::is_string)
                    {
                        let mapped: Vec<Value> = refs
                            .iter()
                            .map(|v| {
                                let s = v.as_str().unwrap_or("");
                                Value::String(if self.identifies(s) {
                                    self.new.slug.clone()
                                } else {
                                    s.to_string()
                                })
                            })
                            .collect();
                        record.insert("rules".into(), Value::Array(mapped));
                    }
                    for key in ["promotedTopic", "topic"] {
                        if let Some(r) = record.get(key).and_then(Value::as_str)
                            && self.identifies(r)
                        {
                            record.insert(key.into(), Value::String(self.new.slug.clone()));
                        }
                    }
                }
                let keys: Vec<String> = record.keys().cloned().collect();
                for key in keys {
                    let current = record[&key].clone();
                    if ["href", "url", "file"].contains(&key.as_str()) && current.is_string() {
                        let text =
                            self.destination(current.as_str().unwrap_or(""), PROJECT_FILE, false);
                        record.insert(key, Value::String(text));
                    } else if ["body", "details", "description", "content"].contains(&key.as_str())
                        && current.is_string()
                    {
                        let text = self.markdown(
                            current.as_str().unwrap_or(""),
                            owner,
                            owner == self.new_file,
                        );
                        record.insert(key, Value::String(text));
                    } else {
                        record.insert(key.clone(), self.rewrite(&current, owner));
                    }
                }
                Value::Object(record)
            }
            other => other.clone(),
        }
    }

    fn run(&self, files: &mut Files) {
        let keys: Vec<String> = files.keys().cloned().collect();
        for key in keys {
            if key.starts_with(".vibedeck/archive/") {
                continue;
            }
            let before = files[&key].clone();
            if key.ends_with(".json")
                && let Ok(json) = serde_json::from_slice::<Value>(&before)
                && (json.is_object() || json.is_array())
            {
                let after = self.rewrite(&json, &key);
                if after != json {
                    files.insert(key, vdjson(&after));
                }
            } else if key.ends_with(".md") {
                let text = String::from_utf8_lossy(&before).into_owned();
                let after = self.markdown(&text, &key, key == self.new_file);
                if text != after {
                    files.insert(key, after.into_bytes());
                }
            }
        }
    }
}

fn last_component(slug: &str) -> &str {
    slug.rsplit('/').next().unwrap_or(slug)
}

fn stage(
    store: &Store,
    action: &Action,
    choice: Option<&str>,
    batch: &str,
    files: &mut Files,
    directories: &mut Vec<String>,
) -> Result<()> {
    match action.kind {
        Kind::Flow => {
            let title = action.title.clone().unwrap_or_default();
            let mut idea = Idea::new(title.clone());
            idea.body = action.content.clone();
            idea.author = Author::Ai;
            let slug = unique_slug(store, &slug::make(&title), Concept::Ideas, files);
            let bytes = json::encode(&idea).map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
            files.insert(
                reorganize_path(&Reference::new(Concept::Ideas, &slug)),
                bytes,
            );
        }
        Kind::Create => {
            let parent =
                paths::normalize_group_path(action.destination.as_deref().unwrap_or(""), true)?;
            let title = action.title.clone().unwrap_or_default();
            let name = slug::make(&title);
            let base = if parent.is_empty() {
                name
            } else {
                format!("{parent}/{name}")
            };
            if action.item.concept == Concept::Rules {
                let slug = unique_slug(store, &base, Concept::Rules, files);
                let mut topic = RuleTopic::new(title);
                topic.author = Author::Ai;
                let bytes =
                    json::encode(&topic).map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
                files.insert(
                    reorganize_path(&Reference::new(Concept::Rules, &slug)),
                    bytes,
                );
            } else {
                let initial = format!(".vibedeck/{}/{base}", action.item.concept.raw());
                let mut path = initial.clone();
                let mut n = 2;
                while reorganize_url(store, &path)?.exists()
                    || directories.contains(&path)
                    || files.keys().any(|k| k.starts_with(&format!("{path}/")))
                {
                    path = format!("{initial}-{n}");
                    n += 1;
                }
                directories.push(path);
            }
        }
        Kind::Move => {
            let group =
                paths::normalize_group_path(action.destination.as_deref().unwrap_or(""), true)?;
            let leaf = last_component(&action.item.slug);
            let slug = if group.is_empty() {
                leaf.to_string()
            } else {
                format!("{group}/{leaf}")
            };
            let target = Reference::new(action.item.concept, &slug);
            if slug == action.item.slug {
                return Ok(());
            }
            let (old, new) = (reorganize_path(&action.item), reorganize_path(&target));
            let data = match files.get(&old) {
                Some(d) if !files.contains_key(&new) && !reorganize_url(store, &new)?.exists() => {
                    d.clone()
                }
                _ => return Err(AiError::ReorganizeOccupied),
            };
            files.insert(new, data);
            files.remove(&old);
            Rewriter::new(store, &action.item, &target).run(files);
        }
        Kind::Merge | Kind::Conflict => {
            let refs = action.references();
            let keeper: Reference = if action.kind == Kind::Conflict {
                let choice = choice.ok_or(AiError::ReorganizeInvalidAction)?;
                refs.iter()
                    .find(|r| r.key() == choice)
                    .cloned()
                    .ok_or(AiError::ReorganizeInvalidAction)?
            } else {
                action.item.clone()
            };
            if !refs.iter().all(|r| {
                r.concept == keeper.concept && r.item_id.is_none() == keeper.item_id.is_none()
            }) {
                return Err(AiError::ReorganizeIncompatible);
            }
            for removed in refs.iter().filter(|r| **r != keeper) {
                if protected(store, removed, files)? {
                    return Err(AiError::ReorganizeIncompatible);
                }
                if action.kind == Kind::Merge {
                    if protected(store, &keeper, files)? {
                        return Err(AiError::ReorganizeIncompatible);
                    }
                    merge(&keeper, removed, files)?;
                }
                let source = reorganize_path(removed);
                let archived = format!(
                    ".vibedeck/archive/reorganize/{batch}/{}/{}{}{}",
                    removed.concept.raw(),
                    removed.slug,
                    removed
                        .item_id
                        .as_ref()
                        .map(|i| format!("-{i}"))
                        .unwrap_or_default(),
                    if removed.concept == Concept::Docs {
                        ".md"
                    } else {
                        ".json"
                    }
                );
                if files.contains_key(&archived) {
                    return Err(AiError::ReorganizeOccupied);
                }
                if let Some(id) = &removed.item_id {
                    let obj = object(removed, files)?;
                    files.insert(archived, vdjson(&Value::Object(obj)));
                    let mut group =
                        object(&Reference::new(Concept::Reviews, &removed.slug), files)?;
                    let kept: Vec<Value> = group
                        .get("items")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default()
                        .into_iter()
                        .filter(|i| i.get("id").and_then(Value::as_str) != Some(id))
                        .collect();
                    group.insert("items".into(), Value::Array(kept));
                    files.insert(source, vdjson(&Value::Object(group)));
                } else if let Some(data) = files.remove(&source) {
                    files.insert(archived, data);
                }
                Rewriter::new(store, removed, &keeper).run(files);
            }
        }
    }
    Ok(())
}

fn prepare(store: &Store, proposal: &Proposal, acceptance: &Acceptance) -> Result<Receipt> {
    if fingerprint(store)? != proposal.fingerprint {
        return Err(AiError::ReorganizeStale);
    }
    let encoded = json::encode(&Answer {
        actions: proposal.actions.clone(),
    })
    .map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
    let validated = parse(&encoded, store, &proposal.fingerprint)?;
    let selected: HashSet<&String> = acceptance.selected.iter().collect();
    let all_ids: HashSet<&String> = proposal.actions.iter().map(|a| &a.id).collect();
    if validated.actions != proposal.actions
        || selected.len() != acceptance.selected.len()
        || !selected.is_subset(&all_ids)
    {
        return Err(AiError::ReorganizeInvalidAction);
    }
    let original = reorganize_bytes(store)?;
    let mut working = original.clone();
    let mut directories: Vec<String> = Vec::new();
    let mut path_moves: BTreeMap<String, String> = BTreeMap::new();
    let mut touched: HashSet<String> = HashSet::new();
    let batch = uuid::Uuid::new_v4().to_string();
    for action in &proposal.actions {
        if !selected.contains(&action.id) {
            continue;
        }
        let choice = acceptance.conflicts.get(&action.id).map(String::as_str);
        // Conflito sem escolha explícita continua pendente, inclusive em "aceitar tudo".
        if action.kind == Kind::Conflict && choice.is_none() {
            continue;
        }
        let refs = action.references();
        if matches!(action.kind, Kind::Merge | Kind::Move | Kind::Conflict)
            && !refs.iter().all(|r| touched.insert(r.key()))
        {
            return Err(AiError::ReorganizeIncompatible);
        }
        if action.kind == Kind::Move {
            let group =
                paths::normalize_group_path(action.destination.as_deref().unwrap_or(""), true)?;
            let leaf = last_component(&action.item.slug);
            let target = if group.is_empty() {
                leaf.to_string()
            } else {
                format!("{group}/{leaf}")
            };
            path_moves.insert(
                reorganize_path(&action.item),
                reorganize_path(&Reference::new(action.item.concept, &target)),
            );
        } else if matches!(action.kind, Kind::Merge | Kind::Conflict) {
            let keeper = if action.kind == Kind::Merge {
                Some(action.item.clone())
            } else {
                refs.iter()
                    .find(|r| Some(r.key().as_str()) == choice)
                    .cloned()
            };
            if let Some(keeper) = keeper
                && keeper.item_id.is_none()
            {
                for r in refs.iter().filter(|r| **r != keeper) {
                    path_moves.insert(reorganize_path(r), reorganize_path(&keeper));
                }
            }
        }
        stage(
            store,
            action,
            choice,
            &batch,
            &mut working,
            &mut directories,
        )?;
    }
    let (mut before, mut after) = (Files::new(), Files::new());
    let keys: BTreeSet<&String> = original.keys().chain(working.keys()).collect();
    for key in keys {
        if original.get(key) != working.get(key) {
            if let Some(v) = original.get(key) {
                before.insert(key.clone(), v.clone());
            }
            if let Some(v) = working.get(key) {
                after.insert(key.clone(), v.clone());
            }
        }
    }
    for key in after.keys() {
        let mut parent: String = key
            .rsplit_once('/')
            .map(|(p, _)| p.to_string())
            .unwrap_or_default();
        while parent.starts_with(".vibedeck/") && !reorganize_url(store, &parent)?.exists() {
            if !directories.contains(&parent) {
                directories.push(parent.clone());
            }
            parent = parent
                .rsplit_once('/')
                .map(|(p, _)| p.to_string())
                .unwrap_or_default();
        }
    }
    directories.sort_by(|a, b| {
        (a.split('/').count(), a.as_str()).cmp(&(b.split('/').count(), b.as_str()))
    });
    Ok(Receipt {
        before,
        after,
        created_directories: directories,
        path_moves,
    })
}

fn commit(store: &Store, receipt: &Receipt, forward: bool) -> Result<()> {
    let (expected, desired) = if forward {
        (&receipt.before, &receipt.after)
    } else {
        (&receipt.after, &receipt.before)
    };
    let keys: BTreeSet<&String> = expected.keys().chain(desired.keys()).collect();
    for key in &keys {
        let url = reorganize_url(store, key)?;
        let current = if url.exists() {
            Some(fs::read(&url).map_err(|e| io_err(&url, e))?)
        } else {
            None
        };
        if current.as_ref() != expected.get(*key) {
            return Err(AiError::ReorganizeStale);
        }
    }
    for dir in &receipt.created_directories {
        if forward && reorganize_url(store, dir)?.exists() {
            return Err(AiError::ReorganizeOccupied);
        }
    }
    let mut applied: Vec<&String> = Vec::new();
    let mut created: Vec<PathBuf> = Vec::new();
    let attempt = (|| -> Result<()> {
        if forward {
            for dir in &receipt.created_directories {
                let url = reorganize_url(store, dir)?;
                fs::create_dir_all(&url).map_err(|e| io_err(&url, e))?;
                created.push(url);
            }
        }
        for key in &keys {
            let url = reorganize_url(store, key)?;
            match desired.get(*key) {
                Some(data) => {
                    write_atomic(&url, data)?;
                }
                None => fs::remove_file(&url).map_err(|e| io_err(&url, e))?,
            }
            applied.push(key);
        }
        if !forward {
            for dir in receipt.created_directories.iter().rev() {
                let url = reorganize_url(store, dir)?;
                if fs::read_dir(&url).is_ok_and(|mut d| d.next().is_none()) {
                    fs::remove_dir(&url).map_err(|e| io_err(&url, e))?;
                }
            }
        }
        Ok(())
    })();
    if let Err(e) = attempt {
        for key in applied.iter().rev() {
            if let Ok(url) = reorganize_url(store, key) {
                match expected.get(*key) {
                    Some(data) => {
                        let _ = write_atomic(&url, data);
                    }
                    None => {
                        let _ = fs::remove_file(&url);
                    }
                }
            }
        }
        for dir in created.iter().rev() {
            let _ = fs::remove_dir_all(dir);
        }
        return Err(e);
    }
    Ok(())
}

/// Aceite explícito é a única entrada que grava. Todas as ações são preparadas antes de confirmar.
pub fn apply(store: &Store, proposal: &Proposal, acceptance: &Acceptance) -> Result<Receipt> {
    let receipt = prepare(store, proposal, acceptance)?;
    commit(store, &receipt, true)?;
    Ok(receipt)
}

/// Desfaz (`forward = false`) ou refaz um recibo; falha se os arquivos mudaram depois.
pub fn restore(store: &Store, receipt: &Receipt, forward: bool) -> Result<()> {
    commit(store, receipt, forward)
}

/// Ações a desmarcar, sem gravar nada. Cada candidata é checada junto com as anteriores compatíveis.
pub fn blockers(
    store: &Store,
    proposal: &Proposal,
    acceptance: &Acceptance,
) -> Result<BTreeMap<String, String>> {
    prepare(
        store,
        proposal,
        &Acceptance {
            selected: vec![],
            conflicts: acceptance.conflicts.clone(),
        },
    )?;
    let ids: HashSet<&String> = proposal.actions.iter().map(|a| &a.id).collect();
    if !acceptance.selected.iter().all(|s| ids.contains(s)) {
        return Err(AiError::ReorganizeInvalidAction);
    }
    let mut compatible: Vec<String> = Vec::new();
    let mut result = BTreeMap::new();
    for action in &proposal.actions {
        if !acceptance.selected.contains(&action.id) {
            continue;
        }
        let mut trial = compatible.clone();
        trial.push(action.id.clone());
        match prepare(
            store,
            proposal,
            &Acceptance {
                selected: trial,
                conflicts: acceptance.conflicts.clone(),
            },
        ) {
            Ok(_) => compatible.push(action.id.clone()),
            Err(
                e @ (AiError::ReorganizeIncompatible
                | AiError::ReorganizeOccupied
                | AiError::ReorganizeInvalidAction),
            ) => {
                result.insert(action.id.clone(), e.to_string());
            }
            Err(e) => return Err(e),
        }
    }
    Ok(result)
}
