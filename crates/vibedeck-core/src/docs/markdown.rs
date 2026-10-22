//! Frontmatter tolerante de Docs (`Markdown` do Swift): `title:`, `tags:` e reescrita da linha `tags:`.
//!
//! Como no Swift, `"\r\n"` é um único caractere e não separa linhas (só `\n` solto separa).

/// `CharacterSet.whitespaces`: tabulação e separadores de espaço (Zs); não inclui quebras de linha.
fn is_inline_ws(c: char) -> bool {
    matches!(
        c,
        '\t' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

fn trim_ws(s: &str) -> &str {
    s.trim_matches(is_inline_ws)
}

/// `text.split(separator: "\n", omittingEmptySubsequences: false)` com `\r\n` como unidade.
fn split_lines(text: &str) -> Vec<&str> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut start = 0;
    for (i, b) in bytes.iter().enumerate() {
        if *b == b'\n' && !(i > 0 && bytes[i - 1] == b'\r') {
            out.push(&text[start..i]);
            start = i + 1;
        }
    }
    out.push(&text[start..]);
    out
}

/// `(frontmatter, corpo)`; frontmatter é `None` quando não há.
fn frontmatter<'a>(lines: &'a [&'a str]) -> (Option<&'a [&'a str]>, &'a [&'a str]) {
    if lines.first().is_some_and(|l| trim_ws(l) == "---")
        && let Some(end) = lines
            .iter()
            .skip(1)
            .position(|l| trim_ws(l) == "---")
            .map(|p| p + 1)
    {
        return (Some(&lines[1..end]), &lines[end + 1..]);
    }
    (None, lines)
}

/// Título: `title:` do frontmatter (aspas e espaços aparados) ou a primeira linha `# `.
pub fn title_of(text: &str) -> Option<String> {
    let lines = split_lines(text);
    let (front, body) = frontmatter(&lines);
    if let Some(value) = front
        .and_then(|f| f.iter().find(|l| l.starts_with("title:")))
        .map(|l| l["title:".len()..].trim_matches([' ', '"', '\'']))
        .filter(|v| !v.is_empty())
    {
        return Some(value.to_string());
    }
    for line in body {
        if let Some(rest) = line.strip_prefix("# ") {
            return Some(trim_ws(rest).to_string()).filter(|s| !s.is_empty());
        }
    }
    None
}

/// Tags: `tags: [a, b]` ou `tags: a, b`.
pub fn tags_of(text: &str) -> Vec<String> {
    let lines = split_lines(text);
    let (front, _) = frontmatter(&lines);
    let Some(line) = front.and_then(|f| f.iter().find(|l| l.starts_with("tags:"))) else {
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

/// `text` com a linha `tags:` trocada, acrescentada (criando o frontmatter) ou removida se `tags` é vazio.
pub fn setting_tags(tags: &[String], text: &str) -> String {
    let tag_line = (!tags.is_empty()).then(|| format!("tags: [{}]", tags.join(", ")));
    let lines = split_lines(text);
    let (front, body) = frontmatter(&lines);
    let mut kept: Vec<String> = front
        .unwrap_or(&[])
        .iter()
        .filter(|l| !l.starts_with("tags:"))
        .map(|l| l.to_string())
        .collect();
    if let Some(line) = tag_line {
        kept.push(line);
    }
    let body_text = body.join("\n");
    if kept.is_empty() {
        return body_text;
    }
    format!("---\n{}\n---\n{}", kept.join("\n"), body_text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn title_from_frontmatter_or_heading() {
        assert_eq!(
            title_of("---\ntitle: \"Olá\"\n---\n# Outro").as_deref(),
            Some("Olá")
        );
        assert_eq!(
            title_of("---\nauthor: ai\n---\n# Meu Doc\n\nx").as_deref(),
            Some("Meu Doc")
        );
        assert_eq!(title_of("sem título"), None);
        assert_eq!(title_of("---\ntitle:\n---\n# H").as_deref(), Some("H"));
        assert_eq!(title_of("#semespaco\n# Real").as_deref(), Some("Real"));
    }

    #[test]
    fn tags_parse_both_forms() {
        assert_eq!(tags_of("---\ntags: [a, b]\n---\n"), ["a", "b"]);
        assert_eq!(tags_of("---\ntags: \"x\", 'y'\n---\n"), ["x", "y"]);
        assert!(tags_of("# sem").is_empty());
    }

    #[test]
    fn setting_tags_rewrites_only_the_tag_line() {
        let t = "---\ntags: [a]\nauthor: ai\n---\n# T\n";
        assert_eq!(
            setting_tags(&["x".into(), "y".into()], t),
            "---\nauthor: ai\ntags: [x, y]\n---\n# T\n"
        );
        assert_eq!(setting_tags(&[], "---\ntags: [a]\n---\n# T"), "# T");
        assert_eq!(
            setting_tags(&["a".into()], "# T"),
            "---\ntags: [a]\n---\n# T"
        );
    }

    #[test]
    fn crlf_is_one_unit_like_swift() {
        assert_eq!(title_of("---\r\ntitle: X\r\n---\r\n"), None);
        assert_eq!(split_lines("a\r\nb\nc"), ["a\r\nb", "c"]);
    }
}
