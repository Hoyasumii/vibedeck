//! Início guiado (MUD-001): estado, descoberta, recusa sem registros e não duplicação.

use std::fs;
use std::path::Path;

use vibedeck_core::Store;
use vibedeck_core::model::{Agent, Author, Command, Skill};
use vibedeck_core::onboarding::{self, ItemRef, OnboardingError, Status, Step};

fn write(root: &Path, rel: &str, text: &str) {
    let p = root.join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, text).unwrap();
}

fn fixture() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "demo", None).unwrap();
    let r = dir.path();
    write(
        r,
        ".claude/agents/reviewer.md",
        "---\nname: reviewer\ndescription: Revisa\n---\nRevise.",
    );
    write(
        r,
        ".claude/commands/ship.md",
        "---\ndescription: Entrega\n---\nShip it.",
    );
    write(
        r,
        ".claude/skills/deploy/SKILL.md",
        "---\nname: deploy\ndescription: Deploy\n---\nDeploy.",
    );
    write(r, ".codex/prompts/plan.md", "Planeje.");
    (dir, store)
}

#[test]
fn pasta_sem_projeto_fica_pendente_e_descobre() {
    let dir = tempfile::tempdir().unwrap();
    write(dir.path(), ".claude/agents/a.md", "---\nname: a\n---\nx");
    let r = onboarding::status_at(dir.path());
    assert!(!r.has_project && r.should_prompt && r.stack_empty);
    assert_eq!(r.step, Step::Stack);
    assert_eq!(r.resources.len(), 1);
    assert!(!dir.path().join(".vibedeck").exists(), "status não escreve");
}

#[test]
fn status_lista_recursos_de_todas_as_origens() {
    let (_d, store) = fixture();
    let r = onboarding::status(&store);
    let kinds: Vec<String> = r
        .resources
        .iter()
        .map(|x| format!("{}:{}", x.kind, x.slug))
        .collect();
    assert_eq!(
        kinds,
        [
            "agent:reviewer",
            "command:ship",
            "command:plan",
            "skill:deploy"
        ]
    );
    assert!(r.resources.iter().all(|x| !x.registered));
    assert_eq!(r.resources[0].origin, ".claude/agents/reviewer.md");
    assert_eq!(r.status, Status::Pending);
    assert!(!r.persisted);
}

#[test]
fn skip_e_retomavel_e_complete_persiste() {
    let (d, store) = fixture();
    let s = onboarding::skip(&store).unwrap();
    assert_eq!(s.status, Status::Skipped);
    let r = onboarding::status(&store);
    assert!(r.persisted && !r.should_prompt && r.status == Status::Skipped);
    assert!(d.path().join(".vibedeck/onboarding.json").is_file());
    // retomar: concluir sobrescreve; o vibedeck.json segue intacto
    onboarding::complete(&store).unwrap();
    assert_eq!(onboarding::status(&store).status, Status::Done);
    assert_eq!(store.project().unwrap().name, "demo");
    // recusar (skip) não cria registros
    assert!(store.list::<Agent>().unwrap().is_empty());
    assert!(store.list::<Command>().unwrap().is_empty());
    assert!(store.list::<Skill>().unwrap().is_empty());
}

#[test]
fn import_cadastra_so_selecionados_e_nao_duplica() {
    let (_d, store) = fixture();
    let sel = [
        ItemRef::parse("agent:reviewer").unwrap(),
        ItemRef::parse("skill:deploy").unwrap(),
    ];
    let out = onboarding::import_selected(&store, &sel, Author::Human).unwrap();
    assert_eq!(out.imported, ["agent:reviewer", "skill:deploy"]);
    assert_eq!(store.list::<Agent>().unwrap().len(), 1);
    assert_eq!(store.list::<Skill>().unwrap().len(), 1);
    assert!(
        store.list::<Command>().unwrap().is_empty(),
        "não selecionado"
    );

    // edição local não é sobrescrita por novo import
    let mut a = store.load::<Agent>("reviewer").unwrap();
    a.summary = Some("editado".into());
    store.save("reviewer", &a).unwrap();
    let again = onboarding::import_selected(&store, &sel, Author::Human).unwrap();
    assert!(again.imported.is_empty());
    assert_eq!(again.already_registered, ["agent:reviewer", "skill:deploy"]);
    assert_eq!(
        store.load::<Agent>("reviewer").unwrap().summary.as_deref(),
        Some("editado")
    );
    assert_eq!(store.list::<Agent>().unwrap().len(), 1);

    let r = onboarding::status(&store);
    let reg: Vec<&str> = r
        .resources
        .iter()
        .filter(|x| x.registered)
        .map(|x| x.slug.as_str())
        .collect();
    assert_eq!(reg, ["reviewer", "deploy"]);
}

#[test]
fn item_desconhecido_ou_invalido_nao_cadastra_nada() {
    let (_d, store) = fixture();
    let sel = [
        ItemRef::parse("agent:reviewer").unwrap(),
        ItemRef::parse("agent:fantasma").unwrap(),
    ];
    let e = onboarding::import_selected(&store, &sel, Author::Human).unwrap_err();
    assert!(matches!(e, OnboardingError::NotFound(_)));
    assert!(store.list::<Agent>().unwrap().is_empty());
    assert!(matches!(
        ItemRef::parse("reviewer"),
        Err(OnboardingError::InvalidItem(_))
    ));
    assert!(matches!(
        ItemRef::parse("foo:bar"),
        Err(OnboardingError::InvalidItem(_))
    ));
}

#[test]
fn projeto_com_stack_sem_estado_conta_como_concluido() {
    let (_d, store) = fixture();
    let mut p = store.project().unwrap();
    p.stack.push(vibedeck_core::model::StackItem {
        icon: "rust".into(),
        name: "Rust".into(),
        category: None,
        note: None,
        tags: vec![],
        author: Author::Human,
    });
    store.save_project(&p).unwrap();
    let r = onboarding::status(&store);
    assert_eq!(r.status, Status::Done);
    assert_eq!(r.step, Step::Patterns);
    assert_eq!(r.stack, ["Rust"]);
}
