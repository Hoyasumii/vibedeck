//! Núcleo da área resources: catálogo de kits, criação/encadeamento, descoberta e importação locais.

use tempfile::TempDir;
use vibedeck_core::Store;
use vibedeck_core::model::{Agent, AiProvider, Author, Command, NextStepKind, Skill};
use vibedeck_core::resources::{self, NewPersona};

fn store() -> (TempDir, Store) {
    let d = TempDir::new().unwrap();
    std::fs::write(d.path().join("vibedeck.json"), "{}").unwrap();
    let s = Store::open(d.path()).unwrap();
    (d, s)
}

fn new(title: &str) -> NewPersona {
    NewPersona {
        title: title.into(),
        ..Default::default()
    }
}

#[test]
fn catalogo_embutido_nao_vazio_e_consistente() {
    let kits = resources::kits();
    assert!(!kits.is_empty());
    for kit in kits {
        assert!(!kit.items.is_empty(), "{}", kit.id);
    }
}

#[test]
fn criar_encadear_e_fluxo() {
    let (_d, s) = store();
    let a = resources::create::<Agent>(&s, new("Um")).unwrap();
    resources::create::<Command>(&s, new("Dois")).unwrap();
    let r = resources::add_next_step::<Agent>(
        &s,
        &a.slug,
        NextStepKind::Command,
        "dois",
        Some(" nota "),
    )
    .unwrap();
    assert_eq!(r.value.next_steps.len(), 1);
    assert_eq!(r.value.next_steps[0].note.as_deref(), Some("nota"));
    // duplicata ignorada
    let r =
        resources::add_next_step::<Agent>(&s, "um", NextStepKind::Command, "dois", None).unwrap();
    assert_eq!(r.value.next_steps.len(), 1);
    assert!(resources::add_next_step::<Agent>(&s, "um", NextStepKind::Agent, "um", None).is_err());
    assert!(
        resources::flow_for(&s, NextStepKind::Agent, "um")
            .unwrap()
            .contains("dois")
    );
    let r = resources::remove_next_step::<Agent>(&s, "um", "dois").unwrap();
    assert!(r.value.next_steps.is_empty());
    assert!(resources::create::<Agent>(&s, new("  ")).is_err());
}

#[test]
fn skill_com_grupo() {
    let (_d, s) = store();
    let mut n = new("Lint");
    n.reference = Some("qualidade/lint".into());
    let r = resources::create::<Skill>(&s, n).unwrap();
    assert_eq!(r.slug, "qualidade/lint");
    assert_eq!(resources::group_path(&r.slug), "qualidade");
}

#[test]
fn descoberta_e_importacao_locais() {
    let (d, s) = store();
    let agents = d.path().join(".claude/agents");
    std::fs::create_dir_all(&agents).unwrap();
    std::fs::write(
        agents.join("rev.md"),
        "---\nname: rev\ndescription: D\n---\nCorpo\n",
    )
    .unwrap();
    let found = resources::discover(d.path());
    let f = found.iter().find(|x| x.name == "rev").expect("descoberto");
    assert!(!f.registered);
    assert_eq!(f.kind, NextStepKind::Agent);
    let r = resources::import_agents(
        &s,
        AiProvider::Claude,
        Some(std::slice::from_ref(&agents)),
        false,
        Author::Ai,
    )
    .unwrap();
    assert_eq!(r.slugs, ["rev"]);
    assert!(
        resources::discover(d.path())
            .iter()
            .find(|x| x.name == "rev")
            .unwrap()
            .registered
    );
}

#[test]
fn skills_codex_sem_dir_sem_codex_da_erro() {
    // Sem --dir a listagem vem do `codex app-server`; com um executável inexistente, erro claro.
    // SAFETY: nenhum outro teste deste binário lê VIBEDECK_CODEX_BIN.
    unsafe { std::env::set_var("VIBEDECK_CODEX_BIN", "/nao/existe/codex") };
    let (_d, s) = store();
    let e = resources::import_skills(&s, AiProvider::Codex, None, false, Author::Ai).unwrap_err();
    assert!(!e.to_string().is_empty());
}
