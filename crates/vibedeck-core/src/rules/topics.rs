//! Tópicos e regras: CRUD sobre `.vibedeck/rules/` (trechos de `ProjectStore.swift`, "// MARK: Rules").

use std::path::Path;

use crate::error::Error;
use crate::model::{ReviewGroup, ReviewItem, Rule, RuleTest, RuleTestMode, RuleTopic, Timestamp};
use crate::paths;
use crate::store::{Record, Store};

use super::error::{Result, RuleError};
use super::rule::{RuleExt, TopicExt, trimmed_non_empty};

pub fn list_topics(store: &Store) -> Result<Vec<Record<RuleTopic>>> {
    Ok(store.rule_topics()?)
}

pub fn resolve_topic_slug(store: &Store, reference: &str) -> Result<String> {
    Ok(store.resolve::<RuleTopic>(reference)?)
}

pub fn load_topic(store: &Store, slug: &str) -> Result<RuleTopic> {
    Ok(store.load::<RuleTopic>(slug)?)
}

pub fn save_topic(store: &Store, topic: &RuleTopic, slug: &str) -> Result<()> {
    store.ensure_directories()?;
    store.save::<RuleTopic>(slug, topic)?;
    Ok(())
}

/// Cria um tópico novo (título aparado; vazio é `Nome inválido.`). Sem `paths`, vale para toda tarefa.
pub fn create_topic(
    store: &Store,
    title: &str,
    description: Option<String>,
    tags: Vec<String>,
    paths: Vec<String>,
    rules: Vec<Rule>,
) -> Result<Record<RuleTopic>> {
    let Some(title) = trimmed_non_empty(title) else {
        return Err(Error::InvalidName.into());
    };
    let mut topic = RuleTopic::new(title);
    topic.description = description;
    topic.tags = tags;
    topic.paths = paths;
    topic.rules = rules;
    let slug = store.new_slug::<RuleTopic>(&topic.title, None)?;
    save_topic(store, &topic, &slug)?;
    Ok(Record { slug, value: topic })
}

/// Lê, aplica `change` e grava o tópico.
pub fn update_topic(
    store: &Store,
    reference: &str,
    change: impl FnOnce(&mut RuleTopic) -> Result<()>,
) -> Result<Record<RuleTopic>> {
    let slug = resolve_topic_slug(store, reference)?;
    let mut topic = load_topic(store, &slug)?;
    change(&mut topic)?;
    save_topic(store, &topic, &slug)?;
    Ok(Record { slug, value: topic })
}

/// Adiciona a regra a um tópico (criado na hora, com `topic_ref` como título, se não resolver).
pub fn add_rule(store: &Store, rule: Rule, topic_ref: &str) -> Result<(String, Rule)> {
    let slug = match resolve_topic_slug(store, topic_ref) {
        Ok(existing) => existing,
        Err(_) => create_topic(store, topic_ref, None, vec![], vec![], vec![])?.slug,
    };
    let appended = rule.clone();
    update_topic(store, &slug, |t| {
        t.rules.push(appended);
        Ok(())
    })?;
    Ok((slug, rule))
}

/// Acha `reference` (id completo ou prefixo >= 4) entre `candidates`; devolve o índice.
pub(super) fn match_rule<'a>(
    reference: &str,
    rules: impl Iterator<Item = &'a Rule>,
) -> Result<usize> {
    let needle = reference.trim().to_lowercase();
    let rules: Vec<&Rule> = rules.collect();
    if let Some(exact) = rules
        .iter()
        .position(|r| r.id.to_string().to_lowercase() == needle)
    {
        return Ok(exact);
    }
    let matches: Vec<usize> = if needle.chars().count() >= 4 {
        rules
            .iter()
            .enumerate()
            .filter(|(_, r)| r.id.to_string().to_lowercase().starts_with(&needle))
            .map(|(i, _)| i)
            .collect()
    } else {
        Vec::new()
    };
    match matches.as_slice() {
        [] => Err(RuleError::RuleNotFound(reference.to_string())),
        [one] => Ok(*one),
        _ => Err(RuleError::AmbiguousRule(reference.to_string())),
    }
}

/// Acha uma regra de tópico por id completo ou prefixo (>= 4): `(slug do tópico, tópico, índice)`.
pub fn find_rule(store: &Store, reference: &str) -> Result<(String, RuleTopic, usize)> {
    let topics = list_topics(store)?;
    let flat: Vec<(usize, usize)> = topics
        .iter()
        .enumerate()
        .flat_map(|(t, rec)| (0..rec.value.rules.len()).map(move |r| (t, r)))
        .collect();
    let at = match_rule(
        reference,
        flat.iter().map(|&(t, r)| &topics[t].value.rules[r]),
    )?;
    let (t, r) = flat[at];
    let rec = &topics[t];
    Ok((rec.slug.clone(), rec.value.clone(), r))
}

pub fn update_rule(store: &Store, reference: &str, change: impl FnOnce(&mut Rule)) -> Result<Rule> {
    let (slug, mut topic, index) = find_rule(store, reference)?;
    change(&mut topic.rules[index]);
    save_topic(store, &topic, &slug)?;
    Ok(topic.rules[index].clone())
}

pub fn delete_rule(store: &Store, reference: &str) -> Result<()> {
    let (slug, mut topic, index) = find_rule(store, reference)?;
    let removed = topic.rules.remove(index);
    save_topic(store, &topic, &slug)?;
    remove_generated_script(store, &removed);
    Ok(())
}

/// Move a regra para o grupo (caminho aninhado dentro do tópico); vazio = raiz do tópico.
pub fn move_rule_to_group(store: &Store, reference: &str, group: &str) -> Result<Rule> {
    let path = paths::normalize_group_path(group, true)?;
    update_rule(store, reference, |rule| {
        rule.group = if path.is_empty() { None } else { Some(path) };
    })
}

/// Renomeia/move um grupo de regras de um tópico (e os subgrupos). Nada é sobrescrito.
pub fn rename_rule_group(store: &Store, topic_ref: &str, from: &str, to: &str) -> Result<()> {
    let slug = resolve_topic_slug(store, topic_ref)?;
    let mut topic = load_topic(store, &slug)?;
    paths::normalize_group_path(from, false)?;
    let target = paths::normalize_group_path(to, false)?;
    if target == from || target.starts_with(&format!("{from}/")) {
        return Err(Error::InvalidGroupPath(to.to_string()).into());
    }
    let inside = |g: &str, base: &str| g == base || g.starts_with(&format!("{base}/"));
    if topic
        .rules
        .iter()
        .any(|r| inside(r.group.as_deref().unwrap_or(""), &target))
    {
        return Err(Error::GroupConflict(target).into());
    }
    for rule in &mut topic.rules {
        if let Some(group) = rule.group.clone()
            && inside(&group, from)
        {
            rule.group = Some(format!("{target}{}", &group[from.len()..]));
        }
    }
    save_topic(store, &topic, &slug)
}

/// Apaga o tópico e solta as ideias e padrões que tinham sido promovidos para ele (como `deleteTopic`).
pub fn delete_topic(store: &Store, slug: &str) -> Result<()> {
    store.delete::<RuleTopic>(slug)?;
    store
        .release_orphaned_ideas()
        .map_err(|e| RuleError::Other(e.to_string()))?;
    store
        .release_orphaned_patterns()
        .map_err(|e| RuleError::Other(e.to_string()))?;
    Ok(())
}

/// Registra como a regra é verificada: um `command` de script (rodado na raiz) ou `manual`.
pub fn set_rule_test(
    store: &Store,
    reference: &str,
    mode: RuleTestMode,
    command: Option<&str>,
    reason: Option<&str>,
) -> Result<Rule> {
    let command = command.and_then(trimmed_non_empty);
    if mode == RuleTestMode::Script && command.is_none() {
        return Err(RuleError::InvalidRuleTest(
            "Informe o comando do script.".to_string(),
        ));
    }
    let reason = reason.and_then(trimmed_non_empty);
    update_rule(store, reference, |rule| {
        rule.test = Some(RuleTest {
            mode,
            command: if mode == RuleTestMode::Script {
                command
            } else {
                None
            },
            reason,
            rule_hash: rule.content_hash(),
            generated_at: Timestamp::now(),
        });
    })
}

/// Esquece o teste da regra (o script gerado, se houver, é apagado também).
pub fn clear_rule_test(store: &Store, reference: &str) -> Result<Rule> {
    let mut previous: Option<Rule> = None;
    let rule = update_rule(store, reference, |r| {
        previous = Some(r.clone());
        r.test = None;
    })?;
    if let Some(previous) = previous {
        remove_generated_script(store, &previous);
    }
    Ok(rule)
}

/// Apaga o script da regra quando mora em `.vibedeck/tests/` (comandos apontados à mão ficam).
fn remove_generated_script(store: &Store, rule: &Rule) {
    let Some(command) = rule
        .test
        .as_ref()
        .and_then(|t| t.command.as_deref())
        .and_then(trimmed_non_empty)
    else {
        return;
    };
    if command.contains(' ') {
        return;
    }
    let url = paths::lexical_normalize(&store.root().join(&command));
    let tests_dir = paths::lexical_normalize(&store.data_dir().join("tests"));
    if url.starts_with(&tests_dir) && url != tests_dir {
        let _ = std::fs::remove_file(url);
    }
}

// ---- escopo de uma tarefa -------------------------------------------------------------------------

/// Caminhos absolutos dentro do projeto viram relativos à raiz; `./` inicial sai.
pub fn relative_path(store: &Store, file: &str) -> String {
    let root = store.root().to_string_lossy().into_owned();
    let root_prefix = if root.ends_with('/') {
        root
    } else {
        format!("{root}/")
    };
    let mut path = if file.starts_with('/') {
        paths::lexical_normalize(Path::new(file))
            .to_string_lossy()
            .into_owned()
    } else {
        file.to_string()
    };
    if let Some(rest) = path.strip_prefix(&root_prefix) {
        path = rest.to_string();
    }
    if let Some(rest) = path.strip_prefix("./") {
        path = rest.to_string();
    }
    path
}

/// Tópicos que valem para uma tarefa: globais (sem `paths`), citados (slug, id ou título) e os que casam
/// algum arquivo tocado. Ordem de `list_topics`.
pub fn applicable_topics(
    store: &Store,
    files: &[String],
    explicit: &[String],
) -> Result<Vec<Record<RuleTopic>>> {
    let relative: Vec<String> = files.iter().map(|f| relative_path(store, f)).collect();
    let mut named = std::collections::HashSet::new();
    for reference in explicit {
        named.insert(resolve_topic_slug(store, reference)?);
    }
    Ok(list_topics(store)?
        .into_iter()
        .filter(|entry| {
            entry.value.is_global()
                || named.contains(&entry.slug)
                || relative.iter().any(|f| entry.value.matches_file(f))
        })
        .collect())
}

/// Item de revisão por id completo ou prefixo único (>= 4) entre todos os grupos.
pub fn find_review_item(store: &Store, reference: &str) -> Result<ReviewItem> {
    let needle = reference.to_lowercase();
    let mut matches: Vec<ReviewItem> = Vec::new();
    for group in store.list::<ReviewGroup>()? {
        for item in group.value.items {
            let id = item.id.to_string().to_lowercase();
            if id == needle {
                return Ok(item);
            }
            if needle.chars().count() >= 4 && id.starts_with(&needle) {
                matches.push(item);
            }
        }
    }
    match matches.len() {
        0 => Err(Error::ItemNotFound(reference.to_string()).into()),
        1 => Ok(matches.remove(0)),
        _ => Err(Error::AmbiguousItem(reference.to_string()).into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Author, RuleSeverity};
    use crate::rules::RuleTestState;

    fn fresh() -> (tempfile::TempDir, Store) {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::init(tmp.path(), "demo", None).unwrap();
        (tmp, store)
    }

    #[test]
    fn topics_and_rules() {
        let (_t, store) = fresh();
        let created = create_topic(
            &store,
            "  Minha Área ",
            Some("desc".into()),
            vec!["t".into()],
            vec!["src/**".into()],
            vec![],
        )
        .unwrap();
        assert_eq!(created.slug, "minha-area");
        assert_eq!(created.value.title, "Minha Área");
        assert!(matches!(
            create_topic(&store, "   ", None, vec![], vec![], vec![]),
            Err(RuleError::Core(Error::InvalidName))
        ));
        let (slug, rule) = add_rule(&store, Rule::new("regra um"), "minha-area").unwrap();
        assert_eq!(slug, "minha-area");
        // tópico criado na hora quando não resolve
        let (slug2, _) = add_rule(&store, Rule::new("outra"), "Novo Tópico").unwrap();
        assert_eq!(slug2, "novo-topico");
        assert_eq!(load_topic(&store, &slug2).unwrap().author, Author::Human);
        let prefix = rule.id.to_string()[..6].to_lowercase();
        let (s, topic, idx) = find_rule(&store, &prefix).unwrap();
        assert_eq!(
            (s.as_str(), idx, topic.rules[idx].text.as_str()),
            ("minha-area", 0, "regra um")
        );
        assert!(matches!(
            find_rule(&store, "abc"),
            Err(RuleError::RuleNotFound(_))
        ));
        assert!(matches!(
            find_rule(&store, "ffffffff-0000"),
            Err(RuleError::RuleNotFound(_))
        ));
        delete_rule(&store, &rule.id.to_string()).unwrap();
        assert!(load_topic(&store, "minha-area").unwrap().rules.is_empty());
    }

    #[test]
    fn ambiguous_prefix() {
        let (_t, store) = fresh();
        let mut a = Rule::new("a");
        let mut b = Rule::new("b");
        a.id = "AAAA0000-0000-4000-8000-000000000001".parse().unwrap();
        b.id = "AAAA0000-0000-4000-8000-000000000002".parse().unwrap();
        add_rule(&store, a, "Geral").unwrap();
        add_rule(&store, b, "Geral").unwrap();
        assert!(matches!(
            find_rule(&store, "aaaa0000"),
            Err(RuleError::AmbiguousRule(_))
        ));
        assert!(find_rule(&store, "AAAA0000-0000-4000-8000-000000000002").is_ok());
    }

    #[test]
    fn set_and_clear_rule_test() {
        let (_t, store) = fresh();
        let (_, rule) = add_rule(&store, Rule::new("regra"), "Geral").unwrap();
        let id = rule.id.to_string();
        assert!(matches!(
            set_rule_test(&store, &id, RuleTestMode::Script, Some("  "), None),
            Err(RuleError::InvalidRuleTest(_))
        ));
        let r = set_rule_test(
            &store,
            &id,
            RuleTestMode::Script,
            Some(" ./x.sh "),
            Some(" porque "),
        )
        .unwrap();
        assert_eq!(r.test_state(), RuleTestState::Script);
        let test = r.test.unwrap();
        assert_eq!(test.command.as_deref(), Some("./x.sh"));
        assert_eq!(test.reason.as_deref(), Some("porque"));
        let r = set_rule_test(&store, &id, RuleTestMode::Manual, Some("ignorado"), None).unwrap();
        assert_eq!(r.test_state(), RuleTestState::Manual);
        assert!(r.test.unwrap().command.is_none());
        let r = clear_rule_test(&store, &id).unwrap();
        assert_eq!(r.test_state(), RuleTestState::None);
    }

    #[test]
    fn delete_and_clear_remove_generated_script_only() {
        let (_t, store) = fresh();
        let (_, generated) = add_rule(&store, Rule::new("gerada"), "Geral").unwrap();
        let (_, manual_path) = add_rule(&store, Rule::new("à mão"), "Geral").unwrap();
        let tests = store.data_dir().join("tests/geral");
        std::fs::create_dir_all(&tests).unwrap();
        std::fs::write(tests.join("g.sh"), "exit 0").unwrap();
        std::fs::write(store.root().join("fora.sh"), "exit 0").unwrap();
        set_rule_test(
            &store,
            &generated.id.to_string(),
            RuleTestMode::Script,
            Some(".vibedeck/tests/geral/g.sh"),
            None,
        )
        .unwrap();
        set_rule_test(
            &store,
            &manual_path.id.to_string(),
            RuleTestMode::Script,
            Some("fora.sh"),
            None,
        )
        .unwrap();
        delete_rule(&store, &generated.id.to_string()).unwrap();
        assert!(!tests.join("g.sh").exists());
        clear_rule_test(&store, &manual_path.id.to_string()).unwrap();
        assert!(store.root().join("fora.sh").exists());
    }

    #[test]
    fn applicable_topics_by_scope() {
        let (_t, store) = fresh();
        create_topic(&store, "Global", None, vec![], vec![], vec![]).unwrap();
        create_topic(
            &store,
            "Swift",
            None,
            vec![],
            vec!["Sources/**".into()],
            vec![],
        )
        .unwrap();
        create_topic(&store, "Docs", None, vec![], vec!["docs/**".into()], vec![]).unwrap();
        let slugs = |files: &[&str], explicit: &[&str]| {
            applicable_topics(
                &store,
                &files.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
                &explicit.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
            )
            .unwrap()
            .into_iter()
            .map(|r| r.slug)
            .collect::<Vec<_>>()
        };
        assert_eq!(slugs(&[], &[]), ["global"]);
        assert_eq!(slugs(&["Sources/A.swift"], &[]), ["global", "swift"]);
        assert_eq!(
            slugs(&["./Sources/A.swift"], &["Docs"]),
            ["docs", "global", "swift"]
        );
        let abs = store.root().join("docs/x.md").display().to_string();
        assert_eq!(slugs(&[&abs], &[]), ["docs", "global"]);
        assert!(applicable_topics(&store, &[], &["nada".into()]).is_err());
    }

    #[test]
    fn relative_path_cases() {
        let (_t, store) = fresh();
        let root = store.root().display().to_string();
        assert_eq!(relative_path(&store, &format!("{root}/a/b.rs")), "a/b.rs");
        assert_eq!(relative_path(&store, "./a/b.rs"), "a/b.rs");
        assert_eq!(relative_path(&store, "a/b.rs"), "a/b.rs");
        assert_eq!(relative_path(&store, "/outro/lugar.rs"), "/outro/lugar.rs");
    }

    #[test]
    fn rule_severity_is_kept() {
        let (_t, store) = fresh();
        let mut r = Rule::new("x");
        r.severity = RuleSeverity::Should;
        r.author = Author::Ai;
        add_rule(&store, r, "Geral").unwrap();
        let t = load_topic(&store, "geral").unwrap();
        assert_eq!(t.rules[0].severity, RuleSeverity::Should);
        assert_eq!(t.rules[0].author, Author::Ai);
    }
}
