//! Docs (`.vibedeck/docs/**/*.md`), grupos de itens, anexos e Docs vinculados por symlink (MUD-002, D4).
//!
//! - `mod.rs`: listar/ler/escrever/criar/apagar docs e resolver referências;
//! - `links`: vínculo automático de todo `.md` da raiz por symlink relativo (contrato no módulo);
//! - `groups`: diretórios de grupo, mover/renomear itens, regras em grupos, recibos de desfazer;
//! - `attachments`: anexos em `.vibedeck/attachments/`;
//! - `generate`: parte pura de `DocGenerate` (prompt/validação de propostas da IA);
//! - `markdown`: frontmatter tolerante.

pub mod attachments;
pub mod error;
pub mod generate;
pub mod groups;
pub mod links;
pub mod markdown;

use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::error::Error;
use crate::model::Author;
use crate::paths;
use crate::slug;
use crate::store::{Store, write_atomic};
use crate::time;

pub use error::{DocError, Result};
pub use links::LinkState;

/// Dados de um vínculo (campo opcional `linked`/`target`/`broken` da saída JSON).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkInfo {
    /// Arquivo da raiz do projeto (ex.: `README.md`).
    pub target: String,
    /// Origem ausente.
    pub broken: bool,
}

/// `DocInfo` do Swift (`slug`, `title`, `tags`, `modified`) mais o vínculo, quando houver.
#[derive(Debug, Clone, PartialEq)]
pub struct DocInfo {
    pub slug: String,
    pub title: String,
    pub tags: Vec<String>,
    pub modified: time::DateTimeUtc,
    pub link: Option<LinkInfo>,
}

impl DocInfo {
    /// `ProjectStore.groupPath(of: slug)`.
    pub fn group(&self) -> String {
        groups::group_path_of(&self.slug)
    }

    /// Campos opcionais do vínculo, só quando vinculado (aditivo): `linked: true`, `target`, `broken`.
    fn link_fields(&self, map: &mut Map<String, Value>) {
        if let Some(l) = &self.link {
            map.insert("linked".into(), json!(true));
            map.insert("target".into(), json!(l.target));
            if l.broken {
                map.insert("broken".into(), json!(true));
            }
        }
    }

    /// `GroupedRecord(slug:value:)` do `docs --json`: `{slug, title, tags, modified, group}` (+ vínculo).
    pub fn to_grouped_json(&self) -> Value {
        let mut m = Map::new();
        m.insert("slug".into(), json!(self.slug));
        m.insert("title".into(), json!(self.title));
        m.insert("tags".into(), json!(self.tags));
        m.insert("modified".into(), json!(time::format_iso(self.modified)));
        m.insert("group".into(), json!(self.group()));
        self.link_fields(&mut m);
        Value::Object(m)
    }

    /// `DocRow` do `list_docs`: `{group, slug, title, tags}` (+ vínculo).
    pub fn to_row_json(&self) -> Value {
        let mut m = Map::new();
        m.insert("group".into(), json!(self.group()));
        m.insert("slug".into(), json!(self.slug));
        m.insert("title".into(), json!(self.title));
        m.insert("tags".into(), json!(self.tags));
        self.link_fields(&mut m);
        Value::Object(m)
    }
}

/// Resultado de uma listagem: docs e avisos (vínculo quebrado, vínculo recusado).
#[derive(Debug, Clone, Default)]
pub struct DocListing {
    pub docs: Vec<DocInfo>,
    pub warnings: Vec<String>,
}

/// Onde um slug de doc mora no disco.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DocFile {
    /// Arquivo (existente ou a criar) dentro de `docs/`.
    Regular(PathBuf),
    /// Symlink saudável: gravar em `target`; `link` continua link.
    Linked { link: PathBuf, target: PathBuf },
    /// Symlink cuja origem não existe.
    Broken { link: PathBuf, name: String },
}

impl DocFile {
    /// Caminho que representa o doc na pasta `docs/` (o link, quando vinculado).
    pub fn path(&self) -> &Path {
        match self {
            DocFile::Regular(p) => p,
            DocFile::Linked { link, .. } | DocFile::Broken { link, .. } => link,
        }
    }
}

pub fn docs_dir(store: &Store) -> PathBuf {
    store.data_dir().join("docs")
}

/// `docURL` + `validatedRecordURL`, com a exceção D4: um symlink de `docs/` para um `.md` da raiz é aceito.
pub fn doc_file(store: &Store, slug: &str) -> Result<DocFile> {
    paths::normalize_group_path(slug, false)?;
    let data = store.data_dir();
    let docs = docs_dir(store);
    let rel = format!("{slug}.md");
    let err = match paths::contained(&data, &docs, &rel) {
        Ok(url) => return Ok(DocFile::Regular(url)),
        Err(e) => e,
    };
    let docs_c = paths::canonical(&docs);
    let data_c = paths::canonical(&data);
    if docs_c == data_c || !docs_c.starts_with(&data_c) {
        return Err(err.into());
    }
    let url = paths::lexical_normalize(&docs_c.join(&rel));
    let is_link = fs::symlink_metadata(&url).is_ok_and(|m| m.file_type().is_symlink());
    let parent_ok = url
        .parent()
        .map(paths::canonical)
        .is_some_and(|p| p == docs_c || p.starts_with(&docs_c));
    if !is_link || !parent_ok {
        return Err(err.into());
    }
    let root_c = paths::canonical(store.root());
    match links::link_state(&root_c, &url) {
        LinkState::Ok { target, .. } => Ok(DocFile::Linked { link: url, target }),
        LinkState::Broken { name, .. } => Ok(DocFile::Broken { link: url, name }),
        LinkState::Rejected => Err(err.into()),
    }
}

/// Comparação "natural" sem caixa/acentos, com números por valor (aproxima `localizedStandardCompare`).
fn natural_cmp(a: &str, b: &str) -> Ordering {
    fn chunks(s: &str) -> Vec<(bool, String)> {
        let mut out: Vec<(bool, String)> = Vec::new();
        for c in slug::fold(s).chars() {
            let d = c.is_ascii_digit();
            match out.last_mut() {
                Some((kind, text)) if *kind == d => text.push(c),
                _ => out.push((d, c.to_string())),
            }
        }
        out
    }
    let (ca, cb) = (chunks(a), chunks(b));
    for (x, y) in ca.iter().zip(cb.iter()) {
        let ord = if x.0 && y.0 {
            let (xt, yt) = (x.1.trim_start_matches('0'), y.1.trim_start_matches('0'));
            xt.len().cmp(&yt.len()).then_with(|| xt.cmp(yt))
        } else {
            x.1.cmp(&y.1)
        };
        if ord != Ordering::Equal {
            return ord;
        }
    }
    ca.len().cmp(&cb.len()).then_with(|| a.cmp(b))
}

fn read_text(path: &Path) -> String {
    fs::read(path)
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or_default()
}

fn mtime(path: &Path) -> time::DateTimeUtc {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .map(time::DateTimeUtc::from)
        .unwrap_or(time::DateTimeUtc::UNIX_EPOCH)
}

/// Sincroniza os vínculos da raiz e lista os docs (título natural crescente). Avisos separados.
pub fn list_docs_detailed(store: &Store) -> Result<DocListing> {
    links::sync_root_links(store);
    let docs = docs_dir(store);
    if !docs.is_dir() {
        return Ok(DocListing::default());
    }
    let docs_c = paths::canonical(&docs);
    let data_c = paths::canonical(&store.data_dir());
    if docs_c == data_c || !docs_c.starts_with(&data_c) {
        return Err(DocError::invalid_path("docs"));
    }
    let root_c = paths::canonical(store.root());
    let mut listing = DocListing::default();
    for entry in links::scan(&docs_c, &root_c) {
        let slug = entry.slug.clone();
        match &entry.link {
            None => {
                let text = read_text(&entry.path);
                listing.docs.push(DocInfo {
                    title: markdown::title_of(&text).unwrap_or_else(|| slug.clone()),
                    tags: markdown::tags_of(&text),
                    modified: mtime(&entry.path),
                    link: None,
                    slug,
                });
            }
            Some(LinkState::Ok { target, name }) => {
                let text = read_text(target);
                listing.docs.push(DocInfo {
                    title: markdown::title_of(&text).unwrap_or_else(|| slug.clone()),
                    tags: markdown::tags_of(&text),
                    modified: mtime(target),
                    link: Some(LinkInfo {
                        target: name.clone(),
                        broken: false,
                    }),
                    slug,
                });
            }
            Some(LinkState::Broken { name, .. }) => {
                listing.warnings.push(format!(
                    "Aviso: o doc vinculado {slug} está quebrado (origem ausente: {name}). Remova só o vínculo com `vibedeck docs unlink {slug}`."
                ));
                listing.docs.push(DocInfo {
                    title: slug.clone(),
                    tags: Vec::new(),
                    modified: fs::symlink_metadata(&entry.path)
                        .and_then(|m| m.modified())
                        .map(time::DateTimeUtc::from)
                        .unwrap_or(time::DateTimeUtc::UNIX_EPOCH),
                    link: Some(LinkInfo {
                        target: name.clone(),
                        broken: true,
                    }),
                    slug,
                });
            }
            Some(LinkState::Rejected) => listing.warnings.push(format!(
                "Aviso: o link {slug}.md aponta para fora de um .md da raiz do projeto e foi ignorado (links não são seguidos)."
            )),
        }
    }
    listing
        .docs
        .sort_by(|a, b| natural_cmp(&a.title, &b.title).then_with(|| a.slug.cmp(&b.slug)));
    Ok(listing)
}

/// `listDocs`.
pub fn list_docs(store: &Store) -> Result<Vec<DocInfo>> {
    Ok(list_docs_detailed(store)?.docs)
}

/// `resolveDocSlug`: caminho exato (com `/`), último componente (ou `Slug.make`) ou título sem caixa.
pub fn resolve_doc_slug(store: &Store, reference: &str) -> Result<String> {
    paths::normalize_group_path(reference, false)?;
    let docs = list_docs(store)?;
    let made = slug::make(reference);
    let last = |s: &str| s.rsplit('/').next().unwrap_or(s).to_string();
    let mut found: Vec<&DocInfo> = docs
        .iter()
        .filter(|d| {
            if reference.contains('/') {
                d.slug == reference
            } else {
                let l = last(&d.slug);
                l == reference || l == made
            }
        })
        .collect();
    if found.is_empty() {
        found = docs
            .iter()
            .filter(|d| d.title.to_lowercase() == reference.to_lowercase())
            .collect();
    }
    if found.len() > 1 {
        return Err(Error::AmbiguousReference {
            reference: reference.to_string(),
            paths: found.iter().map(|d| d.slug.clone()).collect(),
        }
        .into());
    }
    found
        .first()
        .map(|d| d.slug.clone())
        .ok_or_else(|| DocError::DocNotFound(reference.to_string()))
}

/// `readDoc`: texto cru (para vinculado, o do alvo).
pub fn read_doc(store: &Store, reference: &str) -> Result<String> {
    let slug = resolve_doc_slug(store, reference)?;
    let path = match doc_file(store, &slug)? {
        DocFile::Regular(p) => p,
        DocFile::Linked { target, .. } => target,
        DocFile::Broken { name, .. } => {
            return Err(DocError::BrokenLink { slug, target: name });
        }
    };
    if !path.exists() {
        return Err(DocError::DocNotFound(reference.to_string()));
    }
    let bytes = fs::read(&path).map_err(|e| DocError::io(&path, e))?;
    String::from_utf8(bytes).map_err(|e| {
        DocError::io(
            &path,
            std::io::Error::new(std::io::ErrorKind::InvalidData, e),
        )
    })
}

/// `writeDoc`: grava no slug exato. Doc vinculado grava no alvo e o link continua link.
pub fn write_doc(store: &Store, slug: &str, text: &str) -> Result<()> {
    store.ensure_directories()?;
    links::sync_root_links(store);
    match doc_file(store, slug)? {
        DocFile::Regular(p) => write_atomic(&p, text.as_bytes())?,
        DocFile::Linked { target, .. } => {
            let perms = fs::metadata(&target).map(|m| m.permissions()).ok();
            write_atomic(&target, text.as_bytes())?;
            if let Some(p) = perms {
                let _ = fs::set_permissions(&target, p);
            }
        }
        DocFile::Broken { name, .. } => {
            return Err(DocError::BrokenLink {
                slug: slug.to_string(),
                target: name,
            });
        }
    }
    Ok(())
}

/// `createDoc`: slug único a partir do título (ou de `reference`); devolve o slug.
pub fn create_doc(
    store: &Store,
    title: &str,
    body: &str,
    author: Author,
    reference: Option<&str>,
) -> Result<String> {
    store.ensure_directories()?;
    let dir = docs_dir(store);
    let slug = match reference {
        Some(r) => {
            let base = paths::normalize_group_path(r, false)?;
            if base.contains('/') {
                slug::unique(&base, &dir, "md")
            } else {
                slug::unique(&slug::make(&base), &dir, "md")
            }
        }
        None => slug::unique(&slug::make(title), &dir, "md"),
    };
    let frontmatter = if author == Author::Ai {
        "---\nauthor: ai\n---\n"
    } else {
        ""
    };
    write_doc(store, &slug, &format!("{frontmatter}# {title}\n\n{body}"))?;
    Ok(slug)
}

/// `createGeneratedDoc`: proposta aceita da IA; o Core grava a autoria `ai`.
pub fn create_generated_doc(
    store: &Store,
    title: &str,
    body: &str,
    reference: Option<&str>,
) -> Result<String> {
    create_doc(store, title, body, Author::Ai, reference)
}

/// `setDocTags` (resolve a referência antes de gravar).
pub fn set_doc_tags(store: &Store, reference: &str, tags: &[String]) -> Result<()> {
    let slug = resolve_doc_slug(store, reference)?;
    let text = read_doc(store, &slug)?;
    write_doc(store, &slug, &markdown::setting_tags(tags, &text))
}

/// `deleteDoc`: apaga o arquivo; em doc vinculado apaga só o link, nunca a origem.
pub fn delete_doc(store: &Store, slug: &str) -> Result<()> {
    let file = doc_file(store, slug)?;
    let path = file.path();
    fs::remove_file(path).map_err(|e| DocError::io(path, e))
}

/// Remove o vínculo de um doc vinculado (inclusive quebrado). Recusa doc que não seja link.
pub fn unlink_doc(store: &Store, reference: &str) -> Result<String> {
    let slug = resolve_doc_slug(store, reference)?;
    match doc_file(store, &slug)? {
        DocFile::Linked { link, .. } | DocFile::Broken { link, .. } => {
            fs::remove_file(&link).map_err(|e| DocError::io(&link, e))?;
            Ok(slug)
        }
        DocFile::Regular(_) => Err(DocError::NotLinked(slug)),
    }
}
