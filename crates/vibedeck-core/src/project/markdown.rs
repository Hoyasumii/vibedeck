//! Docs vistos pela área de projeto: listagem (slugs/títulos/tags), resolução de referência e
//! `Markdown.settingTags`. É o mínimo que `status`, `get_project` e `tag doc` precisam.
//!
//! INTEGRAÇÃO: quando `docs::` do core existir, `list_docs` e `resolve_doc_slug` devem delegar a ele.

use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};

use super::{ProjectError, Result};
use crate::paths;
use crate::slug;
use crate::store::{self, Store};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocInfo {
    pub slug: String,
    pub title: String,
    pub tags: Vec<String>,
}

pub fn docs_dir(store: &Store) -> PathBuf {
    store.data_dir().join("docs")
}

/// `*.md` recursivo, sem ocultos nem diretórios-link. Um link de arquivo só entra se (D4) apontar para um
/// `.md` regular na raiz do projeto. Ordem: título, "natural" e sem caixa/diacríticos (`localizedStandardCompare`).
pub fn list_docs(store: &Store) -> Result<Vec<DocInfo>> {
    let dir = docs_dir(store);
    let mut files = Vec::new();
    if dir.is_dir() {
        collect(store, &dir, &dir, &mut files)?;
    }
    let mut docs: Vec<DocInfo> = files
        .into_iter()
        .map(|(slug, path)| {
            let text = fs::read_to_string(&path).unwrap_or_default();
            DocInfo {
                title: title_of(&text).unwrap_or_else(|| slug.clone()),
                tags: tags_of(&text),
                slug,
            }
        })
        .collect();
    docs.sort_by(|a, b| standard_compare(&a.title, &b.title).then_with(|| a.slug.cmp(&b.slug)));
    Ok(docs)
}

fn collect(store: &Store, base: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) -> Result<()> {
    let entries = fs::read_dir(dir).map_err(|e| crate::Error::io(dir, e))?;
    for entry in entries {
        let entry = entry.map_err(|e| crate::Error::io(dir, e))?;
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path();
        let Ok(ft) = entry.file_type() else { continue };
        let is_md = path
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("md"));
        if ft.is_symlink() {
            if is_md && links_to_root_md(store, &path) {
                push(base, &path, out);
            }
        } else if ft.is_dir() {
            collect(store, base, &path, out)?;
        } else if ft.is_file() && is_md {
            push(base, &path, out);
        }
    }
    Ok(())
}

fn push(base: &Path, path: &Path, out: &mut Vec<(String, PathBuf)>) {
    let Ok(rel) = path.strip_prefix(base) else {
        return;
    };
    let mut rel = rel.to_path_buf();
    rel.set_extension("");
    let slug = rel
        .components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/");
    out.push((slug, path.to_path_buf()));
}

/// D4: o alvo resolvido é um `.md` regular cujo pai é a raiz do projeto.
fn links_to_root_md(store: &Store, link: &Path) -> bool {
    let Ok(target) = fs::canonicalize(link) else {
        return false;
    };
    let Ok(root) = fs::canonicalize(store.root()) else {
        return false;
    };
    target.is_file()
        && target.parent() == Some(root.as_path())
        && target
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("md"))
}

/// `resolveDocSlug`: caminho com `/` = slug exato; sem `/`, último componente igual à referência ou a
/// `Slug.make(referência)`; senão, título sem caixa.
pub fn resolve_doc_slug(store: &Store, reference: &str) -> Result<String> {
    paths::normalize_group_path(reference, false)?;
    let docs = list_docs(store)?;
    let by_slug: Vec<&DocInfo> = docs
        .iter()
        .filter(|d| {
            if reference.contains('/') {
                d.slug == reference
            } else {
                let last = d.slug.rsplit('/').next().unwrap_or("");
                last == reference || last == slug::make(reference)
            }
        })
        .collect();
    let candidates: Vec<&DocInfo> = if by_slug.is_empty() {
        docs.iter()
            .filter(|d| d.title.to_lowercase() == reference.to_lowercase())
            .collect()
    } else {
        by_slug
    };
    if candidates.len() > 1 {
        return Err(crate::Error::AmbiguousReference {
            reference: reference.to_string(),
            paths: candidates.iter().map(|d| d.slug.clone()).collect(),
        }
        .into());
    }
    candidates
        .first()
        .map(|d| d.slug.clone())
        .ok_or_else(|| ProjectError::DocNotFound(reference.to_string()))
}

pub fn doc_path(store: &Store, slug: &str) -> PathBuf {
    docs_dir(store).join(format!("{slug}.md"))
}

pub fn read_doc(store: &Store, reference: &str) -> Result<String> {
    let slug = resolve_doc_slug(store, reference)?;
    let path = doc_path(store, &slug);
    if !path.is_file() {
        return Err(ProjectError::DocNotFound(reference.to_string()));
    }
    fs::read_to_string(&path).map_err(|e| crate::Error::io(&path, e).into())
}

/// `setDocTags`: reescreve a linha `tags:` do frontmatter (removida se `tags` for vazio).
pub fn set_doc_tags(store: &Store, reference: &str, tags: &[String]) -> Result<()> {
    let text = read_doc(store, reference)?;
    let slug = resolve_doc_slug(store, reference)?;
    let updated = setting_tags(tags, &text);
    store::write_if_changed(&doc_path(store, &slug), updated.as_bytes())?;
    Ok(())
}

fn is_blank(c: char) -> bool {
    c == '\t'
        || (c.is_whitespace()
            && !matches!(
                c,
                '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{85}' | '\u{2028}' | '\u{2029}'
            ))
}

fn trim_ws(s: &str) -> &str {
    s.trim_matches(is_blank)
}

/// Separa o frontmatter YAML: `(Some(linhas), corpo)` ou `(None, todas as linhas)`.
fn frontmatter(text: &str) -> (Option<Vec<&str>>, Vec<&str>) {
    let lines: Vec<&str> = text.split('\n').collect();
    if lines.first().is_some_and(|l| trim_ws(l) == "---")
        && let Some(end) = lines.iter().skip(1).position(|l| trim_ws(l) == "---")
    {
        let end = end + 1;
        return (Some(lines[1..end].to_vec()), lines[end + 1..].to_vec());
    }
    (None, lines)
}

/// Título do frontmatter `title:` ou do primeiro `# `.
pub fn title_of(text: &str) -> Option<String> {
    let (front, body) = frontmatter(text);
    if let Some(value) = front
        .iter()
        .flatten()
        .find(|l| l.starts_with("title:"))
        .map(|l| l["title:".len()..].trim_matches([' ', '"', '\'']))
        .filter(|v| !v.is_empty())
    {
        return Some(value.to_string());
    }
    for line in body {
        if let Some(rest) = line.strip_prefix("# ") {
            return Some(trim_ws(rest))
                .filter(|v| !v.is_empty())
                .map(str::to_string);
        }
    }
    None
}

/// Tags do frontmatter: `tags: [a, b]` ou `tags: a, b`.
pub fn tags_of(text: &str) -> Vec<String> {
    let (front, _) = frontmatter(text);
    let Some(line) = front.iter().flatten().find(|l| l.starts_with("tags:")) else {
        return Vec::new();
    };
    line["tags:".len()..]
        .trim_matches([' ', '[', ']'])
        .split(',')
        .map(|t| t.trim_matches([' ', '"', '\'']))
        .filter(|t| !t.is_empty())
        .map(str::to_string)
        .collect()
}

/// `Markdown.settingTags`: troca, acrescenta (criando o frontmatter) ou remove a linha `tags:`.
pub fn setting_tags(tags: &[String], text: &str) -> String {
    let (front, body) = frontmatter(text);
    let mut lines: Vec<String> = front
        .unwrap_or_default()
        .into_iter()
        .filter(|l| !l.starts_with("tags:"))
        .map(str::to_string)
        .collect();
    if !tags.is_empty() {
        lines.push(format!("tags: [{}]", tags.join(", ")));
    }
    let body_text = body.join("\n");
    if lines.is_empty() {
        return body_text;
    }
    let mut out = String::from("---\n");
    for l in &lines {
        out.push_str(l);
        out.push('\n');
    }
    out.push_str("---\n");
    out.push_str(&body_text);
    out
}

/// Aproxima `localizedStandardCompare`: sem caixa nem diacríticos, números por valor.
pub fn standard_compare(a: &str, b: &str) -> Ordering {
    let (fa, fb) = (slug::fold(a), slug::fold(b));
    let (mut ca, mut cb) = (fa.chars().peekable(), fb.chars().peekable());
    loop {
        match (ca.peek().copied(), cb.peek().copied()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let na = take_number(&mut ca);
                let nb = take_number(&mut cb);
                let ord = na.len().cmp(&nb.len()).then_with(|| na.cmp(&nb));
                if ord != Ordering::Equal {
                    return ord;
                }
            }
            (Some(x), Some(y)) => {
                if x != y {
                    return x.cmp(&y);
                }
                ca.next();
                cb.next();
            }
        }
    }
}

fn take_number(it: &mut std::iter::Peekable<std::str::Chars<'_>>) -> String {
    let mut s = String::new();
    while let Some(c) = it.peek().copied().filter(char::is_ascii_digit) {
        s.push(c);
        it.next();
    }
    s.trim_start_matches('0').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn setting_tags_cria_troca_e_remove() {
        let t = setting_tags(&tags(&["a", "b"]), "# Título\n\ncorpo");
        assert_eq!(t, "---\ntags: [a, b]\n---\n# Título\n\ncorpo");
        assert_eq!(tags_of(&t), ["a", "b"]);
        let t2 = setting_tags(&tags(&["c"]), &t);
        assert_eq!(t2, "---\ntags: [c]\n---\n# Título\n\ncorpo");
        let t3 = setting_tags(&[], &t2);
        assert_eq!(t3, "# Título\n\ncorpo");
        let keep = "---\ntitle: X\ntags: a, b\n---\ncorpo\n";
        assert_eq!(
            setting_tags(&tags(&["z"]), keep),
            "---\ntitle: X\ntags: [z]\n---\ncorpo\n"
        );
    }

    #[test]
    fn titulos() {
        assert_eq!(title_of("---\ntitle: \"Oi\"\n---\n# Outro").unwrap(), "Oi");
        assert_eq!(title_of("# Um\n").unwrap(), "Um");
        assert_eq!(title_of("sem título"), None);
        assert_eq!(title_of("#  \n# Dois"), None);
    }

    #[test]
    fn ordem_natural() {
        assert_eq!(standard_compare("Doc 2", "doc 10"), Ordering::Less);
        assert_eq!(standard_compare("Ação", "acao"), Ordering::Equal);
        assert_eq!(standard_compare("b", "a"), Ordering::Greater);
    }
}
