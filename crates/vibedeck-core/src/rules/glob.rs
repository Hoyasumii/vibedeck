//! `Glob.matches`: globs minimalistas estilo gitignore (`*`, `?`, `**`), ancorados e sensíveis a caixa.

use regex::Regex;

/// Casa `path` (relativo à raiz) com `pattern`. Padrão sem `/` casa o nome em qualquer profundidade; `/`
/// final casa tudo abaixo; `/` inicial ancora na raiz.
pub fn matches(pattern: &str, path: &str) -> bool {
    let mut pattern = pattern.trim_matches([' ', '\t']).to_string();
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
    Regex::new(&to_regex(&pattern)).is_ok_and(|re| re.is_match(path))
}

fn to_regex(pattern: &str) -> String {
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
            other => out.push(other),
        }
    }
    out.push('$');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn globs() {
        assert!(matches("*.swift", "Sources/A/B.swift"));
        assert!(matches("Sources/**", "Sources/A/B.swift"));
        assert!(matches("Sources/", "Sources/A/B.swift"));
        assert!(matches("/README.md", "README.md"));
        assert!(!matches("/README.md", "docs/README.md"));
        assert!(matches("README.md", "docs/README.md"));
        assert!(matches("./Sources/*.swift", "Sources/A.swift"));
        assert!(!matches("Sources/*.swift", "Sources/A/B.swift"));
        assert!(matches("Sources/**/B.swift", "Sources/B.swift"));
        assert!(matches("Sources/**/B.swift", "Sources/x/y/B.swift"));
        assert!(matches("a?.rs", "ab.rs"));
        assert!(!matches("a?.rs", "a/.rs"));
        assert!(!matches("", "x"));
        assert!(!matches("   ", "x"));
        assert!(matches("a+b(1).txt", "a+b(1).txt"));
        assert!(!matches("*.SWIFT", "a.swift"));
        assert!(matches("x/", "./x/y"));
    }
}
