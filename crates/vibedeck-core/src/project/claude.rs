//! Coleção Claude: referências curadas a artefatos/docs do claude.ai, guardadas só em `vibedeck.json`.

use super::{ProjectError, Result};
use crate::model::{ClaudeItem, ClaudeItemKind, Id, Timestamp};
use crate::store::Store;

pub fn kind_title(kind: ClaudeItemKind) -> &'static str {
    match kind {
        ClaudeItemKind::Artifact => "Artefato",
        ClaudeItemKind::Doc => "Doc",
    }
}

pub fn kind_raw(kind: ClaudeItemKind) -> &'static str {
    match kind {
        ClaudeItemKind::Artifact => "artifact",
        ClaudeItemKind::Doc => "doc",
    }
}

pub fn parse_kind(text: &str) -> Option<ClaudeItemKind> {
    match text {
        "artifact" => Some(ClaudeItemKind::Artifact),
        "doc" => Some(ClaudeItemKind::Doc),
        _ => None,
    }
}

fn trim_ws_nl(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace())
}

/// `ClaudeItem.accepts`: http(s) para o host `claude.ai`, sem usuário/senha.
pub fn accepts(text: &str) -> bool {
    let t = trim_ws_nl(text);
    if t.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return false;
    }
    let Some((scheme, rest)) = t.split_once("://") else {
        return false;
    };
    if !scheme.eq_ignore_ascii_case("https") && !scheme.eq_ignore_ascii_case("http") {
        return false;
    }
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    if authority.contains('@') {
        return false;
    }
    let (host, port) = match authority.split_once(':') {
        Some((h, p)) => (h, Some(p)),
        None => (authority, None),
    };
    if port.is_some_and(|p| !p.chars().all(|c| c.is_ascii_digit())) {
        return false;
    }
    host.eq_ignore_ascii_case("claude.ai")
}

/// `ClaudeItem.suggestedTitle`: último componente do caminho, decodificado; vazio → `claude.ai`.
pub fn suggested_title(text: &str) -> String {
    let no_frag = text.split(['#', '?']).next().unwrap_or("");
    let after_scheme = no_frag.split_once("://").map_or(no_frag, |(_, r)| r);
    let path = after_scheme.split_once('/').map_or("", |(_, p)| p);
    let last = path.trim_end_matches('/').rsplit('/').next().unwrap_or("");
    match percent_decode(last) {
        Some(s) if !s.is_empty() => s,
        _ => "claude.ai".into(),
    }
}

/// `removingPercentEncoding`: `None` se houver `%` sem dois dígitos hex ou o resultado não for UTF-8.
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

/// `ClaudeItem.make`: valida a URL (aparada) e usa o título dado (aparado) ou o sugerido.
pub fn make(
    url: &str,
    kind: ClaudeItemKind,
    title: Option<&str>,
    tags: Vec<String>,
) -> Result<ClaudeItem> {
    let url = trim_ws_nl(url);
    if !accepts(url) {
        return Err(ProjectError::InvalidClaudeUrl);
    }
    let title = title.map(trim_ws_nl).unwrap_or("");
    Ok(ClaudeItem {
        id: Id::new(),
        title: if title.is_empty() {
            suggested_title(url)
        } else {
            title.to_string()
        },
        url: url.to_string(),
        kind,
        tags,
        added_at: Timestamp::now(),
    })
}

pub fn list(store: &Store, kind: Option<ClaudeItemKind>) -> Result<Vec<ClaudeItem>> {
    Ok(store
        .project()?
        .claude
        .into_iter()
        .filter(|i| kind.is_none_or(|k| i.kind == k))
        .collect())
}

/// `addClaudeItem`: valida antes de tocar no manifesto (URL inválida não grava nada).
pub fn add(
    store: &Store,
    url: &str,
    kind: ClaudeItemKind,
    title: Option<&str>,
    tags: Vec<String>,
) -> Result<ClaudeItem> {
    let item = make(url, kind, title, tags)?;
    let mut project = store.project()?;
    project.claude.push(item.clone());
    store.save_project(&project)?;
    Ok(item)
}

/// `removeClaudeItem`: id completo, título (sem caixa) ou prefixo do id (>= 4, só se nenhum título casar).
pub fn remove(store: &Store, reference: &str) -> Result<()> {
    let mut project = store.project()?;
    let needle = trim_ws_nl(reference).to_lowercase();
    let id_text = |i: &ClaudeItem| i.id.to_string().to_lowercase();
    let found: Option<ClaudeItem> =
        if let Some(exact) = project.claude.iter().find(|i| id_text(i) == needle) {
            Some(exact.clone())
        } else {
            let titled: Vec<&ClaudeItem> = project
                .claude
                .iter()
                .filter(|i| i.title.to_lowercase() == needle)
                .collect();
            let matches: Vec<&ClaudeItem> = if titled.is_empty() && needle.chars().count() >= 4 {
                project
                    .claude
                    .iter()
                    .filter(|i| id_text(i).starts_with(&needle))
                    .collect()
            } else {
                titled
            };
            match matches.len() {
                0 => return Err(ProjectError::ClaudeItemNotFound(reference.to_string())),
                1 => Some(matches[0].clone()),
                _ => return Err(ProjectError::AmbiguousClaudeItem(reference.to_string())),
            }
        };
    if let Some(item) = found {
        project.claude.retain(|i| i.id != item.id);
    }
    store.save_project(&project)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aceita_so_claude_ai() {
        for u in [
            "https://claude.ai/public/artifacts/abc",
            "http://claude.ai/x",
            "https://CLAUDE.AI/x",
            "https://claude.ai:443/x",
            "https://claude.ai",
        ] {
            assert!(accepts(u), "{u}");
        }
        for u in [
            "https://claude.ai.evil.test/x",
            "https://evil.test/claude.ai",
            "file://claude.ai/x",
            "https://claude.ai@evil.test/x",
            "https://user@claude.ai/x",
            "claude.ai/x",
            "",
            "https://claude.ai:abc/x",
        ] {
            assert!(!accepts(u), "{u}");
        }
    }

    #[test]
    fn titulo_sugerido() {
        assert_eq!(
            suggested_title("https://claude.ai/public/artifacts/example"),
            "example"
        );
        assert_eq!(suggested_title("https://claude.ai"), "claude.ai");
        assert_eq!(suggested_title("https://claude.ai/"), "claude.ai");
        assert_eq!(
            suggested_title("https://claude.ai/x/meu%20doc?a=1"),
            "meu doc"
        );
        assert_eq!(suggested_title("https://claude.ai/x/%zz"), "claude.ai");
        assert_eq!(suggested_title("https://claude.ai/a/b/"), "b");
    }

    #[test]
    fn make_apara_e_valida() {
        let url = "https://claude.ai/public/artifacts/abc";
        let doc = make(
            &format!(" {url}\n"),
            ClaudeItemKind::Doc,
            Some(" Meu doc "),
            vec!["design".into()],
        )
        .unwrap();
        assert_eq!(doc.title, "Meu doc");
        assert_eq!(doc.url, url);
        assert_eq!(
            make(url, ClaudeItemKind::Artifact, Some("  "), vec![])
                .unwrap()
                .title,
            "abc"
        );
        assert!(matches!(
            make("https://example.com", ClaudeItemKind::Doc, None, vec![]),
            Err(ProjectError::InvalidClaudeUrl)
        ));
    }
}
