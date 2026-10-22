//! Casos de uso de ideias (port dos testes Swift de ideias, dependências, grupos e promoção).

use std::collections::HashSet;
use std::fs;

use vibedeck_core::ideas::*;
use vibedeck_core::model::*;
use vibedeck_core::{Error, Record, Store};

fn fresh() -> (tempfile::TempDir, Store) {
    let tmp = tempfile::tempdir().unwrap();
    let store = Store::init(tmp.path(), "demo", None).unwrap();
    (tmp, store)
}

fn mk(store: &Store, title: &str) -> String {
    store
        .create_idea(title, None, &[], Author::Human, None)
        .unwrap()
        .slug
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

fn set_status(store: &Store, slug: &str, status: IdeaStatus) {
    store
        .update_idea(slug, |i| {
            i.status = status;
            Ok(())
        })
        .unwrap();
}

#[test]
fn create_trims_validates_and_groups() {
    let (_t, store) = fresh();
    assert!(matches!(
        store.create_idea("   ", None, &[], Author::Human, None),
        Err(Error::InvalidName)
    ));
    let flat = store
        .create_idea("  Plano  ", Some("corpo"), &s(&["a"]), Author::Ai, None)
        .unwrap();
    assert_eq!(flat.slug, "plano");
    assert_eq!(flat.value.title, "Plano");
    assert_eq!(flat.value.author, Author::Ai);
    assert_eq!(flat.value.body.as_deref(), Some("corpo"));
    let a = store
        .create_idea("X", None, &[], Author::Human, Some("a/b/x"))
        .unwrap();
    assert_eq!(a.slug, "a/b/x");
    let c = store
        .create_idea("X", None, &[], Author::Human, Some("c/x"))
        .unwrap();
    assert_eq!(c.slug, "c/x");
    assert_eq!(store.ideas().unwrap().len(), 3);
    assert_eq!(group_path("a/b/x"), "a/b");
    assert_eq!(
        store.idea(&flat.value.id.to_string()).unwrap().slug,
        "plano"
    );
    assert_eq!(store.idea("a/b/x").unwrap().slug, "a/b/x");
    assert!(matches!(
        store.idea("x"),
        Err(Error::AmbiguousReference { .. })
    ));
    let again = store
        .create_idea("X", None, &[], Author::Human, Some("a/b/x"))
        .unwrap();
    assert_eq!(again.slug, "a/b/x-2");
    for bad in ["../x", "/x", "a//b", ".oculta/x", "a\\b"] {
        assert!(
            store
                .create_idea("X", None, &[], Author::Human, Some(bad))
                .is_err(),
            "{bad}"
        );
    }
    assert!(store.dir::<Idea>().join("a/b/x.json").is_file());
}

#[test]
fn update_stamps_updated_at_and_saves() {
    let (_t, store) = fresh();
    let slug = mk(&store, "Ideia");
    let before = store.load::<Idea>(&slug).unwrap();
    let rec = store
        .update_idea(&slug, |i| {
            i.status = IdeaStatus::Exploring;
            Ok(())
        })
        .unwrap();
    assert_eq!(rec.value.status, IdeaStatus::Exploring);
    assert!(rec.value.updated_at >= before.updated_at);
    assert_eq!(
        store.load::<Idea>(&slug).unwrap().status,
        IdeaStatus::Exploring
    );
    assert!(matches!(
        store.update_idea("nao-existe", |_| Ok(())),
        Err(IdeaError::Core(Error::IdeaNotFound(_)))
    ));
}

fn invalid(r: Result<Record<Idea>, IdeaError>) -> String {
    match r {
        Err(IdeaError::InvalidDependency(m)) => m,
        Err(e) => panic!("erro inesperado: {e}"),
        Ok(_) => panic!("esperava InvalidDependency"),
    }
}

#[test]
fn dependencies_roundtrip_unique_and_integrity() {
    let (_t, store) = fresh();
    let (a, b, c) = (mk(&store, "A"), mk(&store, "B"), mk(&store, "C"));
    let saved = store
        .set_idea_dependencies(&a, &[b.clone(), c.clone(), b.clone()])
        .unwrap();
    assert_eq!(
        saved.value.dependencies,
        vec![
            store.load::<Idea>(&b).unwrap().id,
            store.load::<Idea>(&c).unwrap().id
        ]
    );
    // a chave só existe quando há valores
    let raw = fs::read_to_string(store.dir::<Idea>().join("b.json")).unwrap();
    assert!(!raw.contains("dependencies"));
    store.set_idea_dependencies(&a, &[]).unwrap();
    assert!(
        !fs::read_to_string(store.dir::<Idea>().join("a.json"))
            .unwrap()
            .contains("dependencies")
    );

    assert!(
        invalid(store.add_idea_dependencies(&a, std::slice::from_ref(&a))).contains("de si mesma")
    );
    let unknown = Id::new().to_string();
    assert!(
        invalid(store.add_idea_dependencies(&a, std::slice::from_ref(&unknown))).contains(&unknown)
    );
    assert!(invalid(store.add_idea_dependencies(&a, &s(&["nao-existe"]))).contains("nao-existe"));
    assert!(
        invalid(store.add_idea_dependencies(&a, &[b.clone(), a.clone()])).contains("de si mesma")
    );
    assert!(store.load::<Idea>(&a).unwrap().dependencies.is_empty());

    store
        .add_idea_dependencies(&a, std::slice::from_ref(&b))
        .unwrap();
    let cyc = invalid(store.add_idea_dependencies(&b, std::slice::from_ref(&a)));
    assert!(cyc.contains("ciclo") && cyc.contains("\"B\""));
    store
        .add_idea_dependencies(&b, std::slice::from_ref(&c))
        .unwrap();
    assert!(invalid(store.add_idea_dependencies(&c, std::slice::from_ref(&a))).contains("ciclo"));
    assert_eq!(
        IdeaError::InvalidDependency("x.".into()).to_string(),
        "Dependência inválida: x. Nada foi alterado."
    );
}

#[test]
fn only_done_satisfies_and_blockers_name_every_pending() {
    let (_t, store) = fresh();
    let main = mk(&store, "Principal");
    let d1 = mk(&store, "Primeira");
    let d2 = mk(&store, "Segunda");
    store
        .add_idea_dependencies(&main, &[d1.clone(), d2.clone()])
        .unwrap();
    // dependência removida do projeto continua bloqueando
    let gone = mk(&store, "Some");
    store
        .add_idea_dependencies(&main, std::slice::from_ref(&gone))
        .unwrap();
    let gone_id = store.load::<Idea>(&gone).unwrap().id;
    store.delete_idea(&gone).unwrap();

    let detail = store.idea_detail(&main).unwrap();
    assert_eq!(detail.dependency_blockers.len(), 3);
    assert_eq!(
        detail.dependency_blockers[0].message,
        "Depende de \"Primeira\" (nova)."
    );
    assert_eq!(
        detail.dependency_blockers[2].message,
        format!("Depende de uma ideia ausente: {gone_id}.")
    );
    assert!(detail.dependency_blockers[2].idea.is_none());

    set_status(&store, &d1, IdeaStatus::Done);
    set_status(&store, &d2, IdeaStatus::Approved);
    assert_eq!(
        store.idea_detail(&main).unwrap().dependency_blockers.len(),
        2
    );
    let err = store.require_idea_dependencies_met(&main).unwrap_err();
    assert_eq!(
        err.to_string().lines().next().unwrap(),
        "A ideia não pode ser implementada:"
    );
    assert!(
        err.to_string()
            .contains("\n- Depende de \"Segunda\" (aprovada).")
    );
    let dep = store.idea_detail(&d1).unwrap();
    assert_eq!(dep.dependents.len(), 1);
    assert_eq!(dep.dependents[0].slug, "principal");

    // remover ignora o que não é dependência; a ausente permanece
    store
        .remove_idea_dependencies(&main, &[d1.clone(), "nada".into()])
        .unwrap();
    let after = store.load::<Idea>(&main).unwrap();
    assert!(after.dependencies.contains(&gone_id));
    assert_eq!(after.dependencies.len(), 2);
    // re-adicionar o UUID já gravado de ideia removida é aceito
    store
        .add_idea_dependencies(&main, &[gone_id.to_string()])
        .unwrap();
    assert_eq!(store.load::<Idea>(&main).unwrap().dependencies.len(), 2);
}

#[test]
fn implementable_gate_requires_current_viable_verdict() {
    let (_t, store) = fresh();
    let slug = mk(&store, "Pronta");
    let reasons = |e: IdeaError| match e {
        IdeaError::NotImplementable(r) => r,
        o => panic!("{o}"),
    };
    assert_eq!(
        reasons(store.implementable_idea(&slug).unwrap_err()).len(),
        1
    );
    store
        .update_idea(&slug, |i| {
            i.status = IdeaStatus::Approved;
            i.rules.push(Rule::new("R"));
            i.readiness = Some(IdeaReadiness {
                viable: true,
                missing: vec![],
                checked_at: Timestamp::now(),
                fingerprint: i.content_fingerprint(),
            });
            Ok(())
        })
        .unwrap();
    assert!(store.implementable_idea(&slug).is_ok());
    // dependência pendente bloqueia sem invalidar o veredito
    let other = mk(&store, "Outra");
    store
        .add_idea_dependencies(&slug, std::slice::from_ref(&other))
        .unwrap();
    assert_eq!(
        reasons(store.implementable_idea(&slug).unwrap_err()).len(),
        1
    );
    set_status(&store, &other, IdeaStatus::Done);
    assert!(store.implementable_idea(&slug).is_ok());
    store
        .update_idea(&slug, |i| {
            i.body = Some("novo".into());
            Ok(())
        })
        .unwrap();
    assert!(store.implementable_idea(&slug).is_err());
}

#[test]
fn promote_creates_topic_syncs_and_unpromotes() {
    let (_t, store) = fresh();
    let created = store
        .create_idea("Promovida", None, &[], Author::Human, Some("a/promovida"))
        .unwrap();
    let slug = created.slug;
    let (_, rule) = store.add_idea_rule(&slug, Rule::new("Regra")).unwrap();
    let topic = store.promote_idea(&slug, &HashSet::new()).unwrap();
    assert_eq!(topic, "promovida");
    let t = store.load::<RuleTopic>(&topic).unwrap();
    assert_eq!(t.source_idea, Some(created.value.id));
    assert_eq!(
        t.description.as_deref(),
        Some("Regras vindas da ideia \"Promovida\".")
    );
    assert_eq!(t.rules.len(), 1);
    assert_eq!(t.rules[0].id, rule.id);
    let idea = store.load::<Idea>(&slug).unwrap();
    assert_eq!(idea.promoted_topic.as_deref(), Some("promovida"));
    assert_eq!(idea.status, IdeaStatus::Approved);

    // promover de novo sincroniza em vez de criar outro
    store.add_idea_rule(&slug, Rule::new("Outra")).unwrap();
    assert_eq!(
        store.promote_idea("a/promovida", &HashSet::new()).unwrap(),
        topic
    );
    assert_eq!(store.rule_topics().unwrap().len(), 1);
    assert_eq!(store.load::<RuleTopic>(&topic).unwrap().rules.len(), 2);

    let removed = store.unpromote_idea(&slug).unwrap();
    let un = store.load::<Idea>(&slug).unwrap();
    assert_eq!(removed.as_deref(), Some("promovida"));
    assert!(un.promoted_topic.is_none());
    assert_eq!(un.status, IdeaStatus::Exploring);
    assert_eq!(un.rules.len(), 2);
    assert!(store.rule_topics().unwrap().is_empty());
    assert_eq!(store.unpromote_idea(&slug).unwrap(), None);
}

#[test]
fn promote_keeps_closed_status_and_topic_slug_is_unique() {
    let (_t, store) = fresh();
    let a = mk(&store, "Igual");
    let b = store
        .create_idea("Igual", None, &[], Author::Human, Some("g/outro"))
        .unwrap()
        .slug;
    set_status(&store, &a, IdeaStatus::Done);
    assert_eq!(store.promote_idea(&a, &HashSet::new()).unwrap(), "igual");
    assert_eq!(store.promote_idea(&b, &HashSet::new()).unwrap(), "igual-2");
    assert_eq!(store.load::<Idea>(&a).unwrap().status, IdeaStatus::Done);
    store.unpromote_idea(&a).unwrap();
    assert_eq!(store.load::<Idea>(&a).unwrap().status, IdeaStatus::Done);
}

#[test]
fn orphaned_ideas_are_released_when_topic_disappears() {
    let (_t, store) = fresh();
    let slug = mk(&store, "Orfa");
    let topic = store.promote_idea(&slug, &HashSet::new()).unwrap();
    store.delete_rule_topic(&topic).unwrap();
    assert_eq!(store.release_orphaned_ideas().unwrap(), vec![slug.clone()]);
    let idea = store.load::<Idea>(&slug).unwrap();
    assert!(idea.promoted_topic.is_none());
    assert_eq!(idea.status, IdeaStatus::Exploring);
    assert!(store.release_orphaned_ideas().unwrap().is_empty());
    // despromover com o tópico já inexistente solta o vínculo e devolve None
    store.promote_idea(&slug, &HashSet::new()).unwrap();
    fs::remove_file(store.dir::<RuleTopic>().join("orfa.json")).unwrap();
    assert_eq!(store.unpromote_idea(&slug).unwrap(), None);
    assert!(store.load::<Idea>(&slug).unwrap().promoted_topic.is_none());
}

#[test]
fn promotion_copies_and_merges_paths() {
    let (tmp, store) = fresh();
    fs::create_dir_all(tmp.path().join("Sources/App")).unwrap();
    fs::write(tmp.path().join("Sources/App/View.swift"), "x").unwrap();
    let slug = mk(&store, "Ideia");
    store
        .update_idea(&slug, |i| {
            i.paths = s(&["Sources/App/**", "Sources/Gone/**"]);
            i.rules = vec![Rule::new("R")];
            Ok(())
        })
        .unwrap();
    assert_eq!(
        store.unmatched_idea_paths(&slug).unwrap(),
        s(&["Sources/Gone/**"])
    );
    let skip: HashSet<String> = ["Sources/Gone/**".to_string()].into();
    let topic = store.promote_idea(&slug, &skip).unwrap();
    assert_eq!(
        store.load::<RuleTopic>(&topic).unwrap().paths,
        s(&["Sources/App/**"])
    );

    let mut t = store.load::<RuleTopic>(&topic).unwrap();
    t.paths.push("Tests/**".into());
    store.save_rule_topic(&topic, &t).unwrap();
    store
        .update_idea(&slug, |i| {
            i.paths.push("Package.swift".into());
            Ok(())
        })
        .unwrap();
    assert_eq!(store.promote_idea(&slug, &HashSet::new()).unwrap(), topic);
    assert_eq!(
        store.load::<RuleTopic>(&topic).unwrap().paths,
        s(&[
            "Sources/App/**",
            "Tests/**",
            "Sources/Gone/**",
            "Package.swift"
        ])
    );
    assert!(
        store
            .unmatched_idea_paths(&mk(&store, "Sem"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn project_files_skip_hidden_and_build_dirs() {
    let tmp = tempfile::tempdir().unwrap();
    for f in [
        "a.txt",
        "src/b.rs",
        ".git/x",
        "node_modules/y",
        "target/z",
        ".hid",
        "d/.h2",
    ] {
        let p = tmp.path().join(f);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, "").unwrap();
    }
    let mut files = project_files(tmp.path(), 100);
    files.sort();
    assert_eq!(files, s(&["a.txt", "src/b.rs"]));
}

#[test]
fn detail_json_has_derived_fields() {
    let (_t, store) = fresh();
    let a = mk(&store, "A");
    let b = mk(&store, "B");
    store.add_idea_dependencies(&a, &[b]).unwrap();
    let bytes = vibedeck_core::json::encode(&store.idea_detail(&a).unwrap()).unwrap();
    let json = String::from_utf8(bytes).unwrap();
    for key in [
        "\"slug\" : \"a\"",
        "\"dependents\" : [",
        "\"dependencyBlockers\" : [",
        "\"dependencies\" : [",
        "\"message\" : \"Depende de \\\"B\\\" (nova).\"",
    ] {
        assert!(json.contains(key), "{key}\n{json}");
    }
    let v: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(v["dependents"], serde_json::json!([]));
    assert_eq!(v["dependencyBlockers"][0]["idea"]["status"], "new");
}

#[test]
fn hashes_match_swift_algorithm() {
    // sha256("texto\n")[..8]
    let mut r = Rule::new("texto");
    assert_eq!(rule_content_hash(&r), "ebbc029320093605");
    assert_eq!(rule_test_state(&r), RuleTestState::None);
    r.test = Some(RuleTest {
        mode: RuleTestMode::Script,
        command: Some("true".into()),
        reason: None,
        rule_hash: rule_content_hash(&r),
        generated_at: Timestamp::now(),
    });
    assert_eq!(rule_test_state(&r), RuleTestState::Script);
    r.text = "mudou".into();
    assert_eq!(rule_test_state(&r), RuleTestState::Stale);

    // sha256 de título, corpo, globs e regras unidos por "\n\u{1F}\n"
    let mut i = Idea::new("T");
    assert_eq!(i.content_fingerprint(), "9f90f148b4d42db7");
    i.body = Some("b".into());
    i.paths = s(&["a", "b"]);
    i.rules.push(Rule::new("R"));
    assert_eq!(i.content_fingerprint(), "e7fe229f48d2e797");
}
