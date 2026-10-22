//! Slugs de nome de arquivo (`Slug.make`), nomes únicos e resolução de referências (`resolveSlug`).

use std::path::Path;

use unicode_normalization::{UnicodeNormalization, char::is_combining_mark};

use crate::error::{Error, Result};
use crate::model::Id;

const MAX_LEN: usize = 60;

/// Dobra caixa e diacríticos como `folding([.diacriticInsensitive, .caseInsensitive], en_US_POSIX)`:
/// NFKD, remove marcas combinantes, minúsculas (com `ß`→`ss`).
pub fn fold(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.nfkd().filter(|c| !is_combining_mark(*c)) {
        match ch {
            'ß' | 'ẞ' => out.push_str("ss"),
            c => out.extend(c.to_lowercase()),
        }
    }
    out
}

/// `Slug.make`: só `[a-z0-9]`; o resto vira um único `-` (nunca no começo); sem `-` finais antes de
/// truncar em 60; vazio vira `untitled`. O corte pode terminar em `-` (igual ao Swift).
pub fn make(text: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for ch in fold(text).chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    if out.is_empty() {
        return "untitled".into();
    }
    out.truncate(MAX_LEN); // só ASCII neste ponto
    out
}

/// `uniqueSlug`: `base`, `base-2`, `base-3`... enquanto `base.ext` (ou o diretório `base`, se `ext` vazio) existir.
pub fn unique(base: &str, dir: &Path, ext: &str) -> String {
    let name = |s: &str| {
        if ext.is_empty() {
            s.to_string()
        } else {
            format!("{s}.{ext}")
        }
    };
    let mut slug = base.to_string();
    let mut n = 2;
    while dir.join(name(&slug)).symlink_metadata().is_ok() {
        slug = format!("{base}-{n}");
        n += 1;
    }
    slug
}

/// Dados mínimos de um registro para resolver referências.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub slug: String,
    pub id: Id,
    pub title: String,
}

fn last_component(slug: &str) -> &str {
    slug.rsplit('/').next().unwrap_or(slug)
}

fn eq_ci(a: &str, b: &str) -> bool {
    a.to_lowercase() == b.to_lowercase()
}

fn ambiguous(reference: &str, found: Vec<&Candidate>) -> Error {
    Error::AmbiguousReference {
        reference: reference.to_string(),
        paths: found.into_iter().map(|c| c.slug.clone()).collect(),
    }
}

/// Port de `resolveSlug`: slug (ou só o último componente), `Slug.make(ref)`, prefixo de id (>= 4,
/// minúsculas), id completo, título (case-insensitive). Referência com `/` é caminho exato; se o arquivo não
/// existe tenta só o título. `exists_path` valida a referência (pode falhar com `InvalidGroupPath`) e diz se
/// o arquivo existe. `Ok(None)` = não encontrado (o chamador escolhe o erro do conceito).
pub fn resolve(
    reference: &str,
    candidates: &[Candidate],
    exists_path: impl Fn(&str) -> Result<bool>,
) -> Result<Option<String>> {
    if reference.contains('/') {
        if exists_path(reference)? {
            return Ok(Some(reference.to_string()));
        }
        let titled: Vec<_> = candidates
            .iter()
            .filter(|c| eq_ci(&c.title, reference))
            .collect();
        if titled.len() > 1 {
            return Err(ambiguous(reference, titled));
        }
        return Ok(titled.first().map(|c| c.slug.clone()));
    }
    let needle = reference.to_lowercase();
    let made = make(reference);
    let by_slug: Vec<_> = candidates
        .iter()
        .filter(|c| {
            c.slug == reference
                || last_component(&c.slug) == reference
                || last_component(&c.slug) == made
        })
        .collect();
    if by_slug.len() > 1 {
        return Err(ambiguous(reference, by_slug));
    }
    if let Some(c) = by_slug.first() {
        return Ok(Some(c.slug.clone()));
    }
    if needle.chars().count() >= 4 {
        let prefixed: Vec<_> = candidates
            .iter()
            .filter(|c| c.id.to_string().to_lowercase().starts_with(&needle))
            .collect();
        if prefixed.len() == 1 {
            return Ok(Some(prefixed[0].slug.clone()));
        }
        if prefixed.len() > 1 {
            return Err(ambiguous(reference, prefixed));
        }
    }
    let matches: Vec<_> = candidates
        .iter()
        .filter(|c| c.id.to_string().to_lowercase() == needle || eq_ci(&c.title, reference))
        .collect();
    if matches.len() > 1 {
        return Err(ambiguous(reference, matches));
    }
    if let Some(c) = matches.first() {
        return Ok(Some(c.slug.clone()));
    }
    if exists_path(reference)? {
        return Ok(Some(reference.to_string()));
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_make() {
        assert_eq!(make("Olá, Mundo!"), "ola-mundo");
        assert_eq!(make("  --Ação  &  Reação--  "), "acao-reacao");
        assert_eq!(make("Crème Brûlée"), "creme-brulee");
        assert_eq!(make("Straße"), "strasse");
        assert_eq!(make("ﬁnal ½"), "final-1-2");
        assert_eq!(make("API v2.0"), "api-v2-0");
    }

    #[test]
    fn empty_becomes_untitled() {
        assert_eq!(make(""), "untitled");
        assert_eq!(make("***"), "untitled");
        assert_eq!(make("日本語"), "untitled");
    }

    #[test]
    fn never_starts_with_dash_and_collapses() {
        assert_eq!(make("!!a!!!b!!"), "a-b");
        assert_eq!(make("a---b"), "a-b");
    }

    #[test]
    fn truncates_at_60_possibly_ending_in_dash() {
        let t = "Criar agentes, comandos, skills e workflows pré-definidos que sejam úteis";
        let s = make(t);
        assert_eq!(
            s,
            "criar-agentes-comandos-skills-e-workflows-pre-definidos-que-"
        );
        assert_eq!(s.len(), 60);
        assert!(s.ends_with('-'));
        assert_eq!(make(&"a".repeat(100)).len(), 60);
    }

    #[test]
    fn unique_adds_suffix() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(unique("a", d.path(), "json"), "a");
        std::fs::write(d.path().join("a.json"), "").unwrap();
        assert_eq!(unique("a", d.path(), "json"), "a-2");
        std::fs::write(d.path().join("a-2.json"), "").unwrap();
        assert_eq!(unique("a", d.path(), "json"), "a-3");
        std::fs::create_dir(d.path().join("run")).unwrap();
        assert_eq!(unique("run", d.path(), ""), "run-2");
    }

    fn cands() -> Vec<Candidate> {
        let mk = |slug: &str, id: &str, title: &str| Candidate {
            slug: slug.into(),
            id: id.parse().unwrap(),
            title: title.into(),
        };
        vec![
            mk(
                "alpha",
                "AAAA1111-0000-0000-0000-000000000001",
                "Primeira ideia",
            ),
            mk(
                "grupo/beta",
                "AAAA2222-0000-0000-0000-000000000002",
                "Segunda",
            ),
            mk(
                "gamma",
                "BBBB1111-0000-0000-0000-000000000003",
                "Outra / Com barra",
            ),
        ]
    }

    #[test]
    fn resolve_variants() {
        let c = cands();
        let no = |_: &str| Ok(false);
        assert_eq!(resolve("alpha", &c, no).unwrap().as_deref(), Some("alpha"));
        assert_eq!(
            resolve("beta", &c, no).unwrap().as_deref(),
            Some("grupo/beta")
        );
        assert_eq!(
            resolve("Segunda", &c, no).unwrap().as_deref(),
            Some("grupo/beta")
        );
        assert_eq!(resolve("bbbb", &c, no).unwrap().as_deref(), Some("gamma"));
        assert_eq!(
            resolve("aaaa2", &c, no).unwrap().as_deref(),
            Some("grupo/beta")
        );
        assert_eq!(
            resolve("primeira IDEIA", &c, no).unwrap().as_deref(),
            Some("alpha")
        );
        assert!(resolve("nada", &c, no).unwrap().is_none());
        // prefixo < 4 não vale
        assert!(resolve("bbb", &c, no).unwrap().is_none());
        match resolve("aaaa", &c, no) {
            Err(Error::AmbiguousReference { paths, .. }) => assert_eq!(paths.len(), 2),
            other => panic!("esperava ambíguo: {other:?}"),
        }
        // caminho com / : título tem prioridade quando o arquivo não existe
        assert_eq!(
            resolve("Outra / Com barra", &c, no).unwrap().as_deref(),
            Some("gamma")
        );
        assert!(resolve("x/y", &c, no).unwrap().is_none());
        assert_eq!(
            resolve("x/y", &c, |_| Ok(true)).unwrap().as_deref(),
            Some("x/y")
        );
    }
}
