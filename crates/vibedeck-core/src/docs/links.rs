//! Docs vinculados por symlink (MUD-002, decisão D4).
//!
//! Todo `.md` regular da **raiz** do projeto aparece em Docs como um symlink **relativo** criado
//! automaticamente em `.vibedeck/docs/<slug>.md` -> `../../<ARQUIVO>.md` (`sync_root_links`, chamado ao listar
//! e ao ler). Regras:
//! - o slug é `Slug.make(nome sem .md)`; se já existe um doc com esse nome (em qualquer pasta) o vínculo usa o
//!   sufixo `-raiz` (`readme-raiz`, `readme-raiz-2`, ...);
//! - editar um doc vinculado grava **no alvo** (resolvido antes do `rename` atômico): o link continua link;
//! - apagar/mover um doc vinculado remove/move só o **link** (que é recriado com o texto relativo correto);
//!   a origem nunca é tocada;
//! - link quebrado (origem ausente) continua listado, com aviso (`broken`), e pode ser removido;
//! - nunca se segue link para fora: só vale alvo que seja **arquivo regular `.md` diretamente na raiz** do
//!   projeto. Alvo fora da raiz, em subpasta, encadeado (alvo também é symlink) ou diretório é `Rejected`:
//!   ignorado na listagem (com aviso) e recusado na leitura/escrita;
//! - desvincular (`docs unlink`, `delete_doc` de doc vinculado) grava o nome do arquivo da raiz em
//!   `.vibedeck/docs/.unlinked` (uma linha por nome) e a sincronização o respeita; `docs link <arquivo.md>`
//!   (`link_doc`) tira o nome da lista e recria o vínculo. Um vínculo removido à mão (sem registro) volta.

use std::fs;
use std::path::{Path, PathBuf};

use super::error::{DocError, Result};
use crate::paths;
use crate::slug;
use crate::store::{Store, write_atomic};

/// Arquivo (dentro de `docs/`) com os `.md` da raiz que o usuário desvinculou.
pub const UNLINKED_FILE: &str = ".unlinked";

fn unlinked_path(store: &Store) -> PathBuf {
    store.data_dir().join("docs").join(UNLINKED_FILE)
}

/// Nomes de `.md` da raiz desvinculados (um por linha; vazias ignoradas).
pub fn unlinked(store: &Store) -> std::collections::BTreeSet<String> {
    fs::read_to_string(unlinked_path(store))
        .map(|t| {
            t.lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn save_unlinked(store: &Store, names: &std::collections::BTreeSet<String>) -> Result<()> {
    let path = unlinked_path(store);
    if names.is_empty() {
        return match fs::remove_file(&path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(DocError::io(&path, e)),
            _ => Ok(()),
        };
    }
    let text: String = names.iter().map(|n| format!("{n}\n")).collect();
    write_atomic(&path, text.as_bytes())?;
    Ok(())
}

/// Registra `name` como desvinculado (idempotente).
pub fn mark_unlinked(store: &Store, name: &str) -> Result<()> {
    let mut names = unlinked(store);
    if names.insert(name.to_string()) {
        save_unlinked(store, &names)?;
    }
    Ok(())
}

/// Vincula de novo o `.md` da raiz `file`: tira-o da lista de desvinculados e sincroniza. Devolve o slug.
pub fn link_doc(store: &Store, file: &str) -> Result<String> {
    let name = file.trim();
    let root_c = paths::canonical(store.root());
    let ok = !name.contains('/') && !name.starts_with('.') && is_md(name);
    if !ok || !root_markdown_files(&root_c).iter().any(|n| n == name) {
        return Err(DocError::NotRootMarkdown(name.to_string()));
    }
    store.ensure_directories()?;
    let mut names = unlinked(store);
    if names.remove(name) {
        save_unlinked(store, &names)?;
    }
    sync_root_links(store);
    let docs_c = paths::canonical(&store.data_dir().join("docs"));
    scan(&docs_c, &root_c)
        .into_iter()
        .find(|e| matches!(&e.link, Some(LinkState::Ok { name: n, .. } | LinkState::Broken { name: n, .. }) if n == name))
        .map(|e| e.slug)
        .ok_or_else(|| DocError::NotRootMarkdown(name.to_string()))
}

/// Estado de um symlink dentro de `docs/`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkState {
    /// Alvo é um `.md` regular na raiz. `target` é o caminho absoluto; `name` o nome do arquivo.
    Ok { target: PathBuf, name: String },
    /// Alvo na raiz, mas inexistente.
    Broken { target: PathBuf, name: String },
    /// Fora da raiz, encadeado, diretório ou ilegível: nunca seguir.
    Rejected,
}

pub(crate) fn is_md(name: &str) -> bool {
    name.len() > 3 && name[name.len() - 3..].eq_ignore_ascii_case(".md")
}

/// Estado do symlink `link` em relação à raiz canônica `root_c`.
pub fn link_state(root_c: &Path, link: &Path) -> LinkState {
    let Ok(raw) = fs::read_link(link) else {
        return LinkState::Rejected;
    };
    let Some(link_parent) = link.parent() else {
        return LinkState::Rejected;
    };
    let abs = if raw.is_absolute() {
        paths::lexical_normalize(&raw)
    } else {
        paths::lexical_normalize(&paths::canonical(link_parent).join(&raw))
    };
    if abs.parent() != Some(root_c) {
        return LinkState::Rejected;
    }
    let Some(name) = abs.file_name().map(|n| n.to_string_lossy().into_owned()) else {
        return LinkState::Rejected;
    };
    if !is_md(&name) || name.starts_with('.') {
        return LinkState::Rejected;
    }
    match fs::symlink_metadata(&abs) {
        Ok(m) if m.file_type().is_symlink() => LinkState::Rejected,
        Ok(m) if m.is_file() => LinkState::Ok { target: abs, name },
        Ok(_) => LinkState::Rejected,
        Err(_) => LinkState::Broken { target: abs, name },
    }
}

/// Texto relativo do link `link_dir/<slug>.md` para o arquivo `name` da raiz (`../` por nível abaixo da raiz).
pub fn relative_target(root_c: &Path, link_dir: &Path, name: &str) -> Option<String> {
    let dir = paths::canonical(link_dir);
    let rel = dir.strip_prefix(root_c).ok()?;
    let depth = rel.components().count();
    Some(format!("{}{name}", "../".repeat(depth)))
}

#[cfg(unix)]
pub(crate) fn make_symlink(text: &str, at: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(text, at)
}

#[cfg(not(unix))]
pub(crate) fn make_symlink(_text: &str, _at: &Path) -> std::io::Result<()> {
    Err(std::io::Error::other(
        "symlinks não são suportados nesta plataforma",
    ))
}

/// Um item achado na pasta de docs.
#[derive(Debug, Clone)]
pub(crate) struct DocEntry {
    /// Caminho relativo a `docs/` sem `.md`.
    pub slug: String,
    /// Caminho do arquivo (ou do link) sob `docs/` canônico.
    pub path: PathBuf,
    /// `Some` quando o item é um symlink.
    pub link: Option<LinkState>,
}

/// Enumera `*.md` recursivamente sem seguir symlinks de diretório e sem ocultos. Symlinks de arquivo `.md`
/// entram com seu `LinkState`. Ordem alfabética estável por caminho.
pub(crate) fn scan(docs_c: &Path, root_c: &Path) -> Vec<DocEntry> {
    let mut out = Vec::new();
    walk(docs_c, docs_c, root_c, &mut out);
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

fn walk(base: &Path, dir: &Path, root_c: &Path, out: &mut Vec<DocEntry>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = rd.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let name = e.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let path = e.path();
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        let ft = meta.file_type();
        if ft.is_symlink() {
            if is_md(&name) {
                out.push(DocEntry {
                    slug: slug_of(base, &path),
                    link: Some(link_state(root_c, &path)),
                    path,
                });
            }
        } else if ft.is_dir() {
            walk(base, &path, root_c, out);
        } else if ft.is_file() && is_md(&name) {
            out.push(DocEntry {
                slug: slug_of(base, &path),
                path,
                link: None,
            });
        }
    }
}

fn slug_of(base: &Path, path: &Path) -> String {
    let rel = path.strip_prefix(base).unwrap_or(path);
    let text = rel
        .components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/");
    text[..text.len() - 3].to_string()
}

fn last_component(slug: &str) -> &str {
    slug.rsplit('/').next().unwrap_or(slug)
}

/// Cria os vínculos que faltam para os `.md` da raiz. Melhor esforço: falhas de E/S (pasta somente leitura,
/// plataforma sem symlink) são ignoradas e a listagem segue com o que existe. Devolve os slugs criados.
pub fn sync_root_links(store: &Store) -> Vec<String> {
    let mut created = Vec::new();
    let data = store.data_dir();
    let root_c = paths::canonical(store.root());
    let candidates = root_markdown_files(&root_c);
    if candidates.is_empty() {
        return created;
    }
    let docs_dir = data.join("docs");
    if fs::create_dir_all(&docs_dir).is_err() {
        return created;
    }
    let docs_c = paths::canonical(&docs_dir);
    let data_c = paths::canonical(&data);
    if docs_c == data_c || !docs_c.starts_with(&data_c) {
        return created;
    }
    let entries = scan(&docs_c, &root_c);
    let ignored = unlinked(store);
    let mut taken: std::collections::HashSet<String> = entries
        .iter()
        .map(|e| last_component(&e.slug).to_lowercase())
        .collect();
    for name in candidates {
        let already = entries.iter().any(|e| {
            matches!(&e.link, Some(LinkState::Ok { name: n, .. } | LinkState::Broken { name: n, .. }) if *n == name)
        });
        if already || ignored.contains(&name) {
            continue;
        }
        let base = slug::make(&name[..name.len() - 3]);
        let mut slug = base.clone();
        if taken.contains(&slug.to_lowercase()) {
            slug = format!("{base}-raiz");
            let mut n = 2;
            while taken.contains(&slug.to_lowercase()) {
                slug = format!("{base}-raiz-{n}");
                n += 1;
            }
        }
        let Some(text) = relative_target(&root_c, &docs_c, &name) else {
            continue;
        };
        if make_symlink(&text, &docs_c.join(format!("{slug}.md"))).is_ok() {
            taken.insert(slug.to_lowercase());
            created.push(slug);
        }
    }
    created
}

/// `.md` regulares (não symlink, não ocultos) diretamente na raiz, em ordem alfabética.
fn root_markdown_files(root_c: &Path) -> Vec<String> {
    let Ok(rd) = fs::read_dir(root_c) else {
        return Vec::new();
    };
    let mut names: Vec<String> = rd
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| is_md(n) && !n.starts_with('.'))
        .collect();
    names.sort();
    names
}

/// Symlinks de arquivo `.md` sob `path` (o próprio `path` se for um link) com alvo da raiz (ok ou quebrado).
pub(crate) fn links_under(root_c: &Path, path: &Path) -> Vec<(PathBuf, String)> {
    let mut out = Vec::new();
    let Ok(meta) = fs::symlink_metadata(path) else {
        return out;
    };
    let keep = |p: &Path, out: &mut Vec<(PathBuf, String)>| match link_state(root_c, p) {
        LinkState::Ok { name, .. } | LinkState::Broken { name, .. } => {
            out.push((p.to_path_buf(), name))
        }
        LinkState::Rejected => {}
    };
    if meta.file_type().is_symlink() {
        keep(path, &mut out);
    } else if meta.is_dir() {
        let mut stack = vec![path.to_path_buf()];
        while let Some(dir) = stack.pop() {
            let Ok(rd) = fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let p = e.path();
                let Ok(m) = fs::symlink_metadata(&p) else {
                    continue;
                };
                if m.file_type().is_symlink() {
                    keep(&p, &mut out);
                } else if m.is_dir() {
                    stack.push(p);
                }
            }
        }
    }
    out.sort();
    out
}

/// Recria cada link em `at` (já movido) com o texto relativo correto para a nova profundidade.
pub(crate) fn relink(root_c: &Path, at: &Path, name: &str) {
    let Some(parent) = at.parent() else { return };
    let Some(text) = relative_target(root_c, parent, name) else {
        return;
    };
    let _ = fs::remove_file(at);
    let _ = make_symlink(&text, at);
}
