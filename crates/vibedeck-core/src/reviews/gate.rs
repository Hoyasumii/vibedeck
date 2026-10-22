//! Gate de conclusão de itens de revisão (dados.md §5.5).
//!
//! Item com regras (explícitas, as de tópicos globais ou as de tópicos cujos `paths` casam
//! `target.file`) só vai a `done` se o último check do item passou e respondeu todas as regras do escopo;
//! regras manuais `must` sem resposta seguram o item.
//!
//! PEDIDO-INTEGRAÇÃO: esta é a leitura mínima de checks/tópicos que a área de regras também precisa
//! (`Glob`, `Rule.contentHash`, `testState`, `applicableTopics`, `relativePath`). Quando `rules` existir,
//! unificar e deixar este módulo só com `verification_problems`/`ensure_verified`.

use std::path::Path;

use regex::Regex;
use sha2::{Digest, Sha256};

use super::{ReviewError, ReviewResult, find_item};
use crate::error::Result;
use crate::model::*;
use crate::paths;
use crate::store::{Record, Store};

/// `RuleTestState` do Swift.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleTestState {
    None,
    Script,
    Manual,
    Stale,
}

impl RuleTestState {
    /// O agente precisa responder a regra num check (tudo que não é decidido por script).
    pub fn needs_agent(self) -> bool {
        self != RuleTestState::Script
    }
}

/// `Rule.contentHash`: 8 primeiros bytes (hex) do SHA-256 de `text + "\n" + (details ?? "")`.
pub fn rule_content_hash(rule: &Rule) -> String {
    let data = format!("{}\n{}", rule.text, rule.details.as_deref().unwrap_or(""));
    let digest = Sha256::digest(data.as_bytes());
    let bytes: &[u8] = digest.as_ref();
    bytes.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// `Rule.testState`.
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

fn is_blank_space(c: char) -> bool {
    c.is_whitespace() && c != '\n' && c != '\r'
}

/// `Glob.matches`: globs estilo gitignore mínimo (`*` dentro do segmento, `?`, `**` em qualquer
/// profundidade). Sem `/` casa o nome do arquivo em qualquer nível; `/` final casa tudo abaixo.
pub fn glob_matches(pattern: &str, path: &str) -> bool {
    let mut pattern = pattern.trim_matches(is_blank_space).to_string();
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
    Regex::new(&glob_regex(&pattern)).is_ok_and(|re| re.is_match(path))
}

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
            _ => out.push(ch),
        }
    }
    out.push('$');
    out
}

/// `RuleTopic.matches(file:)`.
pub fn topic_matches_file(topic: &RuleTopic, file: &str) -> bool {
    topic.paths.iter().any(|p| glob_matches(p, file))
}

/// `ProjectStore.relativePath`: caminhos absolutos dentro do projeto viram relativos à raiz; remove `./`.
pub fn relative_path(root: &Path, file: &str) -> String {
    let mut root_path = root.to_string_lossy().into_owned();
    if !root_path.ends_with('/') {
        root_path.push('/');
    }
    let mut path = if file.starts_with('/') {
        paths::lexical_normalize(Path::new(file))
            .to_string_lossy()
            .into_owned()
    } else {
        file.to_string()
    };
    if let Some(rest) = path.strip_prefix(&root_path) {
        path = rest.to_string();
    }
    if let Some(rest) = path.strip_prefix("./") {
        path = rest.to_string();
    }
    path
}

/// `applicableTopics`: globais, as que casam algum arquivo e as citadas (slug, id ou título).
pub fn applicable_topics(
    store: &Store,
    files: &[String],
    explicit: &[String],
) -> Result<Vec<Record<RuleTopic>>> {
    let relative: Vec<String> = files
        .iter()
        .map(|f| relative_path(store.root(), f))
        .collect();
    let named: std::collections::HashSet<String> = explicit
        .iter()
        .map(|r| store.resolve::<RuleTopic>(r))
        .collect::<Result<_>>()?;
    Ok(store
        .rule_topics()?
        .into_iter()
        .filter(|t| {
            t.value.is_global()
                || named.contains(&t.slug)
                || relative.iter().any(|f| topic_matches_file(&t.value, f))
        })
        .collect())
}

/// Tópicos que seguram o item: `rules` explícitos + os que casam `target.file` (+ globais).
pub fn required_topics(store: &Store, item: &ReviewItem) -> Result<Vec<Record<RuleTopic>>> {
    let files: Vec<String> = item
        .target
        .as_ref()
        .and_then(|t| t.file.clone())
        .into_iter()
        .collect();
    applicable_topics(store, &files, &item.rules)
}

/// Por que o item ainda não pode ser concluído (vazio = verificado). O último check do item precisa ter
/// passado e respondido toda regra atual dos tópicos exigidos.
pub fn verification_problems(store: &Store, item: &ReviewItem) -> Result<Vec<String>> {
    let required = required_topics(store, item)?;
    let rules: Vec<(&str, &Rule)> = required
        .iter()
        .flat_map(|t| t.value.rules.iter().map(move |r| (t.slug.as_str(), r)))
        .collect();
    if rules.is_empty() {
        return Ok(vec![]);
    }
    // `checks()` vem do mais novo para o mais antigo.
    let Some(record) = store
        .checks()?
        .into_iter()
        .find(|c| c.check.review_item == Some(item.id))
    else {
        let slugs: Vec<&str> = required.iter().map(|t| t.slug.as_str()).collect();
        return Ok(vec![format!(
            "Nenhum check registrado para este item (tópicos: {}).",
            slugs.join(", ")
        )]);
    };
    let check = record.check;
    if !check.passed {
        return Ok(check
            .failures
            .iter()
            .map(|f| format!("Falhou no último check: {f}"))
            .collect());
    }
    let answered: std::collections::HashSet<Id> = check.results.iter().map(|r| r.rule_id).collect();
    let mut problems = Vec::new();
    for (slug, rule) in rules {
        if answered.contains(&rule.id) {
            continue;
        }
        if !rule_test_state(rule).needs_agent() {
            problems.push(format!(
                "Regra nova desde o último check: [{slug}] {}",
                rule.text
            ));
        } else if rule.severity == RuleSeverity::Must {
            // Um check só de scripts deixa as manuais sem verificar: só as obrigatórias seguram o item.
            problems.push(format!(
                "Regra manual obrigatória sem verificação: [{slug}] {} (envie o check com as regras manuais respondidas)",
                rule.text
            ));
        }
    }
    Ok(problems)
}

/// `RulesNotVerified` a menos que o item possa ser marcado `done`.
pub fn ensure_verified(store: &Store, item_ref: &str) -> ReviewResult<()> {
    let (_, group, index) = find_item(store, item_ref)?;
    let problems = verification_problems(store, &group.items[index])?;
    if problems.is_empty() {
        Ok(())
    } else {
        Err(ReviewError::RulesNotVerified(problems))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn globs() {
        assert!(glob_matches("Sources/App/**", "Sources/App/Side.swift"));
        assert!(glob_matches("Sources/App/**", "Sources/App/a/b/Side.swift"));
        assert!(!glob_matches("Sources/App/**", "Sources/Core/x.swift"));
        assert!(glob_matches("*.swift", "Sources/App/Side.swift"));
        assert!(glob_matches("Sources/*.swift", "Sources/A.swift"));
        assert!(!glob_matches("Sources/*.swift", "Sources/x/A.swift"));
        assert!(glob_matches("**/x.rs", "x.rs"));
        assert!(glob_matches("a/?.rs", "a/b.rs"));
        assert!(glob_matches("docs/", "docs/a/b.md"));
        assert!(glob_matches("./src/**", "src/a.rs"));
        assert!(glob_matches("/src/a.rs", "./src/a.rs"));
        assert!(!glob_matches("  ", "a"));
        assert!(!glob_matches("a.rs", "ba.rs.x"));
        assert!(glob_matches("a.rs", "x/a.rs"));
    }

    #[test]
    fn caminho_relativo() {
        let root = Path::new("/p/proj");
        assert_eq!(relative_path(root, "/p/proj/src/./a.rs"), "src/a.rs");
        assert_eq!(relative_path(root, "./src/a.rs"), "src/a.rs");
        assert_eq!(relative_path(root, "/outro/a.rs"), "/outro/a.rs");
    }

    #[test]
    fn hash_e_estado_do_teste() {
        let mut rule = Rule::new("texto");
        assert_eq!(rule_content_hash(&rule).len(), 16);
        assert_eq!(rule_test_state(&rule), RuleTestState::None);
        let hash = rule_content_hash(&rule);
        rule.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some("true".into()),
            reason: None,
            rule_hash: hash.clone(),
            generated_at: Timestamp::now(),
        });
        assert_eq!(rule_test_state(&rule), RuleTestState::Script);
        rule.test.as_mut().unwrap().command = Some("  ".into());
        assert_eq!(rule_test_state(&rule), RuleTestState::Manual);
        rule.text = "outro".into();
        assert_eq!(rule_test_state(&rule), RuleTestState::Stale);
        assert!(rule_test_state(&rule).needs_agent());
    }
}
