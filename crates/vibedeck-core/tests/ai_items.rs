//! Itens com IA (`ItemDiscoverTests`), catálogo paginado e política de IA.

use std::collections::BTreeMap;
use std::fs;

use vibedeck_core::Store;
use vibedeck_core::ai::item::{self, Kind, Proposal, Refs};
use vibedeck_core::ai::{AiError, catalog};
use vibedeck_core::model::{Agent, Author, Command, Skill, Workflow};

fn new_store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "Projeto", None).unwrap();
    (dir, store)
}

fn snapshot(store: &Store) -> BTreeMap<String, Vec<u8>> {
    walkdir::WalkDir::new(store.data_dir())
        .into_iter()
        .flatten()
        .filter(|e| e.file_type().is_file())
        .map(|e| {
            (
                e.path().to_string_lossy().into_owned(),
                fs::read(e.path()).unwrap(),
            )
        })
        .collect()
}

fn agent_proposal(title: &str, prompt: &str) -> Proposal {
    Proposal {
        prompt: prompt.into(),
        ..Proposal::new(title)
    }
}

fn add_agent(store: &Store, title: &str, summary: Option<&str>, prompt: &str) -> String {
    let mut agent = Agent::new(title);
    agent.summary = summary.map(str::to_string);
    agent.prompt = prompt.into();
    store.create(&agent, None).unwrap().slug
}

#[test]
fn agente_valido_e_normalizado() {
    let data = r#"{"title":" Revisor ","summary":"Revisa PRs","model":"","tools":["Read"," "],"prompt":" Você revisa. ","tags":["a","a"," "]}"#;
    let p = item::parse(Kind::Agent, data.as_bytes(), None).unwrap();
    assert_eq!(p.title, "Revisor");
    assert_eq!(p.model, None);
    assert_eq!(p.tools, ["Read"]);
    assert_eq!(p.prompt, "Você revisa.");
    assert_eq!(p.tags, ["a"]);
}

#[test]
fn json_invalido_da_erro_em_portugues_e_nao_grava() {
    let (_d, store) = new_store();
    let before = snapshot(&store);
    assert!(item::parse(Kind::Skill, "não é json".as_bytes(), None).is_err());
    let e = item::parse(Kind::Skill, b"{", None)
        .unwrap_err()
        .to_string();
    assert!(e.contains("JSON válido"), "{e}");
    assert!(e.starts_with("O Claude Code não conseguiu descobrir; nada foi alterado.\n"));
    assert_eq!(snapshot(&store), before);
}

#[test]
fn campos_vazios_ou_brancos_sao_rejeitados() {
    assert!(item::validated(Kind::Agent, &agent_proposal("   ", "x"), None).is_none());
    assert!(item::validated(Kind::Command, &agent_proposal("x", " \n "), None).is_none());
    assert!(item::validated(Kind::Workflow, &Proposal::new("x"), None).is_none());
    assert!(item::parse(Kind::Agent, br#"{"title":"","prompt":"x"}"#, None).is_err());
}

#[test]
fn conteudo_e_limitado() {
    let big = "a".repeat(item::MAX_CONTENT_LENGTH + 1);
    assert!(item::validated(Kind::Agent, &agent_proposal("x", &big), None).is_none());
    let ok = "a".repeat(item::MAX_CONTENT_LENGTH);
    assert!(item::validated(Kind::Agent, &agent_proposal("x", &ok), None).is_some());
}

#[test]
fn etapas_de_workflow_sao_checadas_contra_itens_existentes() {
    let refs = Refs {
        agents: ["revisor".to_string()].into(),
        ..Refs::default()
    };
    let json = br#"{"title":"Fluxo","steps":[{"id":"Revisor","kind":"agent","ref":"revisor","transitions":[{"verdict":"OK","to":"revisor"},{"to":"fantasma"}]}]}"#;
    let p = item::parse(Kind::Workflow, json, Some(&refs)).unwrap();
    assert_eq!(
        p.steps.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(),
        ["revisor"]
    );
    assert_eq!(p.steps[0].transitions.len(), 1);
    let other = Refs {
        agents: ["outro".to_string()].into(),
        ..Refs::default()
    };
    assert!(item::parse(Kind::Workflow, json, Some(&other)).is_err());
}

#[test]
fn colisao_de_slug_nunca_sobrescreve() {
    let (_d, store) = new_store();
    let existing = add_agent(&store, "Revisor", None, "original");
    let slug = item::create_item(&store, Kind::Agent, &agent_proposal("Revisor", "novo")).unwrap();
    assert_ne!(slug, existing);
    assert_eq!(store.load::<Agent>(&existing).unwrap().prompt, "original");
    let created = store.load::<Agent>(&slug).unwrap();
    assert_eq!(created.prompt, "novo");
    assert_eq!(created.author, Author::Ai);
}

#[test]
fn cria_todos_os_tipos_como_ia() {
    let (_d, store) = new_store();
    let a = item::create_item(&store, Kind::Agent, &agent_proposal("A", "p")).unwrap();
    let c = item::create_item(
        &store,
        Kind::Command,
        &Proposal {
            argument_hint: Some("<x>".into()),
            ..agent_proposal("C", "p")
        },
    )
    .unwrap();
    let s = item::create_item(
        &store,
        Kind::Skill,
        &Proposal {
            summary: Some("quando".into()),
            ..agent_proposal("S", "p")
        },
    )
    .unwrap();
    let step: vibedeck_core::model::WorkflowStep =
        serde_json::from_value(serde_json::json!({"id": "a", "kind": "agent", "ref": a})).unwrap();
    let w = item::create_item(
        &store,
        Kind::Workflow,
        &Proposal {
            steps: vec![step],
            ..Proposal::new("W")
        },
    )
    .unwrap();
    assert_eq!(
        store.load::<Command>(&c).unwrap().argument_hint.as_deref(),
        Some("<x>")
    );
    assert_eq!(store.load::<Skill>(&s).unwrap().author, Author::Ai);
    let wf = store.load::<Workflow>(&w).unwrap();
    assert_eq!(wf.steps.len(), 1);
    assert_eq!(wf.author, Author::Ai);
}

#[test]
fn prompt_inclui_conteudo_atual_e_gerar_nao_grava() {
    let (_d, store) = new_store();
    add_agent(&store, "Revisor", None, "texto atual único");
    let before = snapshot(&store);
    let current = item::item_proposal(&store, Kind::Agent, "revisor").unwrap();
    let existing = item::existing_items(&store, Kind::Agent).unwrap();
    let prompt = item::prompt(Kind::Agent, "mais curto", Some(&current), &existing, &[]);
    assert!(prompt.contains("texto atual único"));
    assert!(prompt.contains("mais curto"));
    assert!(prompt.contains("COMPLETO"));
    assert!(!item::prompt(Kind::Agent, "x", None, &[], &[]).contains("Conteúdo atual"));
    let (p, s) =
        item::item_ai_prompt(&store, Kind::Agent, "  mais curto ", Some("revisor")).unwrap();
    assert!(p.contains("Pedido do usuário:\nmais curto"));
    assert!(s.starts_with("{\"additionalProperties\":false,"));
    assert_eq!(snapshot(&store), before);
    let blank = item::item_ai_prompt(&store, Kind::Agent, "  ", None).unwrap_err();
    assert!(
        blank
            .to_string()
            .ends_with("Descreva o que a IA deve fazer.")
    );
}

#[test]
fn editar_substitui_conteudo_mantendo_identidade_e_fluxo() {
    let (_d, store) = new_store();
    let created = add_agent(&store, "Revisor", None, "velho");
    let other = add_agent(&store, "Outro", None, "");
    let mut agent = store.load::<Agent>(&created).unwrap();
    agent.next_steps =
        vec![serde_json::from_value(serde_json::json!({"kind": "agent", "ref": other})).unwrap()];
    store.save_agent(&created, &agent).unwrap();
    let id = agent.id;
    item::apply_item(
        &store,
        Kind::Agent,
        &created,
        &agent_proposal("Revisor 2", "novo"),
    )
    .unwrap();
    let edited = store.load::<Agent>(&created).unwrap();
    assert_eq!(edited.prompt, "novo");
    assert_eq!(edited.title, "Revisor 2");
    assert_eq!(edited.id, id);
    assert_eq!(edited.next_steps.len(), 1);
    // item_ai_apply devolve a própria referência ao editar e o slug ao criar
    let json = br#"{"title":"Revisor 3","prompt":"p3"}"#;
    assert_eq!(
        item::item_ai_apply(&store, Kind::Agent, json, Some("revisor")).unwrap(),
        "revisor"
    );
    assert_eq!(
        item::item_ai_apply(&store, Kind::Agent, json, None).unwrap(),
        "revisor-3"
    );
}

#[test]
fn schema_e_json_valido_para_todos_os_tipos() {
    for kind in [Kind::Agent, Kind::Command, Kind::Skill, Kind::Workflow] {
        let v = item::schema_value(kind);
        assert_eq!(v["additionalProperties"], false);
        let required: Vec<&str> = v["required"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r.as_str().unwrap())
            .collect();
        let mut sorted = required.clone();
        sorted.sort();
        assert_eq!(required, sorted);
        assert!(!item::schema(kind).contains(": "));
    }
    assert!(item::Kind::parse("nope").is_none());
}

#[test]
fn catalogo_pagina_sem_enviar_prompts_do_usuario() {
    let (_d, store) = new_store();
    let secret = "instrução personalizada".repeat(100);
    for name in ["A", "B", "C"] {
        add_agent(&store, name, Some("Uso específico"), &secret);
    }
    let first = catalog::catalog(&store, "agents", 0, 2).unwrap();
    assert_eq!(
        (first.items.len(), first.next_offset, first.total),
        (2, Some(2), 3)
    );
    let last = catalog::catalog(&store, "agents", 2, 2).unwrap();
    assert_eq!((last.items.len(), last.next_offset), (1, None));
    let text = String::from_utf8(vibedeck_core::json::encode(&first).unwrap()).unwrap();
    assert!(!text.contains(&secret));
    assert!(text.contains("\"ref\" : \"a\""));
    assert_eq!(store.load::<Agent>("a").unwrap().prompt, secret);
    assert!(matches!(
        catalog::catalog(&store, "agents", -1, 2),
        Err(AiError::InvalidRange)
    ));
    assert!(matches!(
        catalog::catalog(&store, "agents", 0, 101),
        Err(AiError::InvalidRange)
    ));
    assert!(matches!(
        catalog::catalog(&store, "agents", 4, 2),
        Err(AiError::InvalidRange)
    ));
    let e = catalog::catalog(&store, "x", 0, 2).unwrap_err().to_string();
    assert!(
        e.ends_with("Catálogo inválido: use agents, commands, skills, workflows ou rules."),
        "{e}"
    );
    // regras trazem os globs (vazio também)
    store
        .create(&vibedeck_core::model::RuleTopic::new("Geral"), None)
        .unwrap();
    let rules = catalog::catalog(&store, "rules", 0, 20).unwrap();
    assert_eq!(rules.items[0].paths.as_deref(), Some(&[][..]));
}
