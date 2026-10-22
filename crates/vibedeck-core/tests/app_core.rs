//! Superfície do app: escrita genérica, lixeira, anexos, revisão, ideias como pedido e recibos.

use std::collections::{BTreeMap, HashSet};
use std::fs;

use serde_json::Value;
use vibedeck_core::ai::reorganize::{self, Acceptance, Action, Answer, Concept, Kind, Reference};
use vibedeck_core::app::{self, RecordKind};
use vibedeck_core::ideas::IdeaFingerprint;
use vibedeck_core::model::{
    Agent, Author, Idea, IdeaReadiness, IdeaStatus, NextStepKind, Rule, RuleTopic, Timestamp,
};
use vibedeck_core::workflows;
use vibedeck_core::{Store, json as vdjson};

fn store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "Projeto", None).unwrap();
    (dir, store)
}

fn trash_files(store: &Store) -> Vec<String> {
    let base = store.data_dir().join(".trash");
    walkdir::WalkDir::new(&base)
        .into_iter()
        .flatten()
        .filter(|e| e.file_type().is_file())
        .map(|e| {
            e.path()
                .strip_prefix(&base)
                .unwrap()
                .components()
                .skip(1)
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/")
        })
        .collect()
}

#[test]
fn put_record_valida_cria_subpastas_e_preserva_autoria() {
    let (_d, store) = store();
    let mut idea = Idea::new("Ideia de grupo");
    idea.author = Author::Human;
    let text = String::from_utf8(vdjson::encode(&idea).unwrap()).unwrap();
    app::put_record(&store, RecordKind::Ideas, "grupo/sub/ideia", &text).unwrap();
    let loaded: Idea = store.load("grupo/sub/ideia").unwrap();
    let sent: Idea = serde_json::from_str(&text).unwrap();
    assert_eq!(loaded.author, Author::Human);
    assert_eq!(loaded.id, idea.id);
    assert_eq!(loaded.created_at, sent.created_at);

    // bytes canônicos: regravar o mesmo texto não muda o arquivo
    let path = store.data_dir().join("ideas/grupo/sub/ideia.json");
    assert_eq!(fs::read_to_string(&path).unwrap(), text);

    // não há temporários sobrando
    let leftovers: Vec<_> = fs::read_dir(path.parent().unwrap())
        .unwrap()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
        .collect();
    assert!(leftovers.is_empty());
}

#[test]
fn put_record_recusa_json_invalido_kind_invalido_e_slug_fora_da_pasta() {
    let (_d, store) = store();
    let bad_json = app::put_record(&store, RecordKind::Rules, "x", "{não é json");
    assert!(bad_json.unwrap_err().0.contains("Registro inválido"));
    let missing_title = app::put_record(&store, RecordKind::Rules, "x", "{}");
    assert!(missing_title.is_err());
    assert!(!store.data_dir().join("rules/x.json").exists());
    assert!(
        app::RecordKind::parse("docs")
            .unwrap_err()
            .0
            .contains("Tipo de registro inválido")
    );
    let topic = serde_json::to_string(&RuleTopic::new("T")).unwrap();
    assert!(app::put_record(&store, RecordKind::Rules, "../fora", &topic).is_err());
    assert!(app::put_record(&store, RecordKind::Rules, "/abs", &topic).is_err());
}

#[test]
fn put_record_cobre_todos_os_tipos() {
    let (_d, store) = store();
    let cases: [(RecordKind, &str, Value); 7] = [
        (
            RecordKind::Reviews,
            "g/revisao",
            serde_json::to_value(vibedeck_core::model::ReviewGroup::new("Revisão")).unwrap(),
        ),
        (
            RecordKind::Rules,
            "g/topico",
            serde_json::to_value(RuleTopic::new("Tópico")).unwrap(),
        ),
        (
            RecordKind::Ideas,
            "ideia",
            serde_json::to_value(Idea::new("Ideia")).unwrap(),
        ),
        (
            RecordKind::Agents,
            "agente",
            serde_json::to_value(Agent::new("Agente")).unwrap(),
        ),
        (
            RecordKind::Commands,
            "comando",
            serde_json::to_value(vibedeck_core::model::Command::new("Comando")).unwrap(),
        ),
        (
            RecordKind::Skills,
            "g/skill",
            serde_json::to_value(vibedeck_core::model::Skill::new("Skill")).unwrap(),
        ),
        (
            RecordKind::Workflows,
            "fluxo",
            serde_json::to_value(vibedeck_core::model::Workflow::new("Fluxo")).unwrap(),
        ),
    ];
    for (kind, slug, value) in &cases {
        app::put_record(&store, *kind, slug, &value.to_string()).unwrap();
    }
    assert!(store.data_dir().join("rules/g/topico.json").is_file());
    assert!(store.data_dir().join("skills/g/skill.json").is_file());
    assert!(store.data_dir().join("agents/agente.json").is_file());
    // agentes/comandos/workflows não aceitam subpasta no listing: o slug continua válido para gravar
    assert_eq!(store.list::<Agent>().unwrap().len(), 1);
}

#[test]
fn delete_record_manda_para_a_lixeira_e_solta_ideias_do_topico() {
    let (_d, store) = store();
    let mut idea = Idea::new("Com regras");
    idea.rules = vec![Rule::new("Faça X")];
    let idea = store.create(&idea, None).unwrap();
    let topic = store.promote_idea(&idea.slug, &HashSet::new()).unwrap();
    assert_eq!(
        store.load::<Idea>(&idea.slug).unwrap().promoted_topic,
        Some(topic.clone())
    );

    app::delete_record(&store, RecordKind::Rules, &topic).unwrap();
    assert!(!store.record_path::<RuleTopic>(&topic).unwrap().exists());
    assert_eq!(
        store.load::<Idea>(&idea.slug).unwrap().promoted_topic,
        None,
        "a ideia promovida é solta"
    );
    let trashed = trash_files(&store);
    assert_eq!(trashed, vec![format!("rules/{topic}.json")]);

    // o conteúdo da lixeira volta pelo put_record
    let base = store.data_dir().join(".trash");
    let saved = fs::read_dir(&base).unwrap().next().unwrap().unwrap().path();
    let text = fs::read_to_string(saved.join(format!("rules/{topic}.json"))).unwrap();
    app::put_record(&store, RecordKind::Rules, &topic, &text).unwrap();
    assert!(store.load::<RuleTopic>(&topic).is_ok());

    assert!(
        app::delete_record(&store, RecordKind::Ideas, "nao-existe")
            .unwrap_err()
            .0
            .contains("Ideia não encontrada")
    );
}

#[test]
fn delete_record_repetido_nao_sobrescreve_a_lixeira() {
    let (_d, store) = store();
    for round in 0..3 {
        let text = serde_json::to_string(&Agent::new(format!("A{round}"))).unwrap();
        app::put_record(&store, RecordKind::Agents, "a", &text).unwrap();
        app::delete_record(&store, RecordKind::Agents, "a").unwrap();
    }
    assert_eq!(trash_files(&store).len(), 3);
}

#[test]
fn put_project_grava_e_so_sincroniza_readme_se_a_stack_mudou() {
    let (_d, store) = store();
    let mut project = store.project().unwrap();
    project.name = "Outro".into();
    let text = String::from_utf8(vdjson::encode(&project).unwrap()).unwrap();
    // stack vazia e README ausente: nada a sincronizar, sem rede
    assert_eq!(app::put_project(&store, &text).unwrap(), None);
    assert_eq!(store.project().unwrap().name, "Outro");
    assert!(!store.root().join("README.md").exists());
    assert!(
        app::put_project(&store, "{")
            .unwrap_err()
            .0
            .contains("Projeto inválido")
    );
    assert_eq!(store.project().unwrap().name, "Outro");
}

#[test]
fn delete_doc_comum_vai_para_a_lixeira_e_vinculado_remove_so_o_vinculo() {
    let (_d, store) = store();
    docs_create(&store);
    let slug = app::delete_doc(&store, "Meu doc").unwrap();
    assert_eq!(slug, "meu-doc");
    assert!(!store.data_dir().join("docs/meu-doc.md").exists());
    assert_eq!(trash_files(&store), vec!["docs/meu-doc.md".to_string()]);

    #[cfg(unix)]
    {
        fs::write(store.root().join("NOTAS.md"), "# Notas\n").unwrap();
        let link = store.data_dir().join("docs/notas.md");
        std::os::unix::fs::symlink("../../NOTAS.md", &link).unwrap();
        let removed = app::delete_doc(&store, "notas").unwrap();
        assert_eq!(removed, "notas");
        assert!(!link.exists());
        assert!(store.root().join("NOTAS.md").exists(), "a origem fica");
        assert_eq!(
            trash_files(&store).len(),
            1,
            "vínculo não vai para a lixeira"
        );
    }
}

fn docs_create(store: &Store) {
    vibedeck_core::docs::create_doc(store, "Meu doc", "corpo", Author::Human, None).unwrap();
}

#[test]
fn anexo_base64_vira_arquivo_e_link() {
    let (_d, store) = store();
    let bytes = [0u8, 1, 2, 250, 251, 252, 253];
    let data = app::decode_base64("AAEC+vv8/Q==").unwrap();
    assert_eq!(data, bytes);
    let link = app::import_attachment(&store, "docs-x", "Foto Legal.PNG", &data).unwrap();
    assert!(
        link.starts_with("![Foto Legal.PNG](../attachments/"),
        "{link}"
    );
    let file = fs::read_dir(store.data_dir().join("attachments"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap();
    assert_eq!(fs::read(file.path()).unwrap(), bytes);
    // dono em subpasta: ../ por componente
    let nested = app::import_attachment(&store, "grupo/ideia", "a.txt", b"oi").unwrap();
    assert!(nested.starts_with("[a.txt](../../attachments/"), "{nested}");
    assert!(app::decode_base64("###").is_err());
}

#[test]
fn revisao_muda_com_arquivos_e_ignora_lixeira() {
    let (_d, store) = store();
    let first = app::revision(store.root());
    assert_eq!(first, app::revision(store.root()), "estável sem mudanças");
    let text = serde_json::to_string(&Idea::new("Nova")).unwrap();
    app::put_record(&store, RecordKind::Ideas, "nova", &text).unwrap();
    let second = app::revision(store.root());
    assert_ne!(first, second);
    fs::create_dir_all(store.data_dir().join(".trash/x")).unwrap();
    fs::write(store.data_dir().join(".trash/x/y.json"), "{}").unwrap();
    assert_eq!(second, app::revision(store.root()));
    let mut project = store.project().unwrap();
    project.name = "Mudou o nome do projeto".into();
    store.save_project(&project).unwrap();
    assert_ne!(second, app::revision(store.root()));
}

fn viable(idea: &mut Idea) {
    idea.status = IdeaStatus::Approved;
    idea.rules = vec![Rule::new("Teste tudo")];
    idea.readiness = Some(IdeaReadiness {
        viable: true,
        missing: vec![],
        checked_at: Timestamp::now(),
        fingerprint: idea.content_fingerprint(),
    });
}

fn workflow_with_step(store: &Store) -> String {
    let agent = store.create(&Agent::new("Dev"), None).unwrap();
    let wf = workflows::create_workflow(store, "Fluxo", None, None, None, vec![], Author::Human)
        .unwrap();
    workflows::add_workflow_step(store, &wf.slug, NextStepKind::Agent, &agent.slug, None).unwrap();
    wf.slug
}

#[test]
fn idea_implement_promove_e_liga_a_execucao_da_ideia() {
    let (_d, store) = store();
    let flow = workflow_with_step(&store);
    let mut idea = Idea::new("Fazer coisa");
    viable(&mut idea);
    let rec = store.create(&idea, None).unwrap();

    assert!(
        app::idea_run(&store, &rec.slug, &flow).unwrap().is_none(),
        "sem execução ainda"
    );
    let first =
        app::idea_implement(&store, &rec.slug, Some(&flow), false, None, &HashSet::new()).unwrap();
    let run_ref = first.run_ref.clone().unwrap();
    assert!(run_ref.starts_with(&format!("{flow}/")));
    assert!(first.prompt.contains("Fazer coisa"));
    assert!(first.prompt.contains(&first.topic));
    assert!(store.load::<RuleTopic>(&first.topic).is_ok());
    let found = app::idea_run(&store, &rec.slug, &flow).unwrap().unwrap();
    assert_eq!(found.0, run_ref);

    // mesma ideia de novo: retoma a mesma execução; restart abre novo ciclo
    let again =
        app::idea_implement(&store, &rec.slug, Some(&flow), false, None, &HashSet::new()).unwrap();
    assert_eq!(again.run_ref.as_deref(), Some(run_ref.as_str()));
    let cycle = again.run.unwrap().cycle;
    let restarted =
        app::idea_implement(&store, &rec.slug, Some(&flow), true, None, &HashSet::new()).unwrap();
    assert_eq!(restarted.run.unwrap().cycle, cycle + 1);

    // sem workflow: só promove e devolve o prompt
    let plain = app::idea_implement(&store, &rec.slug, None, false, None, &HashSet::new()).unwrap();
    assert!(plain.run_ref.is_none() && plain.run.is_none());
    assert_eq!(plain.topic, first.topic);
}

#[test]
fn idea_implement_recusa_ideia_inelegivel_e_workflow_vazio() {
    let (_d, store) = store();
    let idea = store.create(&Idea::new("Crua"), None).unwrap();
    let e = app::idea_implement(&store, &idea.slug, None, false, None, &HashSet::new());
    assert!(e.unwrap_err().0.contains("aprovada"));

    let mut ready = Idea::new("Pronta");
    viable(&mut ready);
    let ready = store.create(&ready, None).unwrap();
    let empty =
        workflows::create_workflow(&store, "Vazio", None, None, None, vec![], Author::Ai).unwrap();
    let e = app::idea_implement(
        &store,
        &ready.slug,
        Some(&empty.slug),
        false,
        None,
        &HashSet::new(),
    );
    assert!(e.unwrap_err().0.contains("não tem etapas"));
    assert!(
        store
            .load::<Idea>(&ready.slug)
            .unwrap()
            .promoted_topic
            .is_none(),
        "recusa antes de promover"
    );
}

#[test]
fn execucao_checkpoint_resume_saida_e_delete() {
    let (_d, store) = store();
    let flow = workflow_with_step(&store);
    let (reference, run, _) =
        workflows::start_run(&store, &flow, Some("entrada"), None, None).unwrap();
    let step = run.current.clone().unwrap();

    let r = app::run_checkpoint(&store, &reference, &step, None, "parcial", false).unwrap();
    assert_eq!(r, reference);
    let saved = workflows::load_run(&store, &reference).unwrap();
    let checkpoint = saved.checkpoint.unwrap();
    assert_eq!(
        (checkpoint.output.as_str(), checkpoint.completed),
        ("parcial", false)
    );
    assert!(
        app::run_checkpoint(&store, &reference, "outra", None, "x", false)
            .unwrap_err()
            .0
            .contains("transição inválida")
    );

    workflows::stop_run(&store, &reference, Some("pausa")).unwrap();
    let (_, resumed) = app::run_resume(&store, &reference).unwrap();
    assert_eq!(
        resumed.status,
        vibedeck_core::model::WorkflowRunStatus::Running
    );

    let note = workflows::save_run_output(&store, &reference, "saída longa").unwrap();
    assert!(note.contains("outputs/"), "{note}");

    workflows::delete_run(&store, &reference).unwrap();
    assert!(workflows::load_run(&store, &reference).is_err());
}

#[test]
fn recibo_de_reorganizacao_faz_ida_e_volta_pelo_json() {
    let (_d, store) = store();
    let topic = store
        .create(&RuleTopic::new("Regras soltas"), None)
        .unwrap();
    let mut action = Action::new(
        Kind::Move,
        Reference::new(Concept::Rules, &topic.slug),
        "Agrupar",
    );
    action.destination = Some("grupo".into());
    let answer = vdjson::encode(&Answer {
        actions: vec![action.clone()],
    })
    .unwrap();
    let proposal =
        reorganize::parse(&answer, &store, &reorganize::fingerprint(&store).unwrap()).unwrap();
    let receipt = reorganize::apply(
        &store,
        &proposal,
        &Acceptance {
            selected: vec![action.id.clone()],
            conflicts: BTreeMap::new(),
        },
    )
    .unwrap();
    let moved = format!("grupo/{}", topic.slug);
    assert!(store.load::<RuleTopic>(&moved).is_ok());

    // o JSON do recibo traz os bytes em base64 padrão (Data do Swift) e volta idêntico
    let text = serde_json::to_string(&receipt).unwrap();
    let value: Value = serde_json::from_str(&text).unwrap();
    let after = value["after"].as_object().unwrap();
    assert!(after.values().all(|v| v.as_str().unwrap().len() % 4 == 0));
    let decoded: reorganize::Receipt = serde_json::from_str(&text).unwrap();
    assert_eq!(decoded, receipt);

    app::reorganize_restore(&store, &text, false).unwrap();
    assert!(store.load::<RuleTopic>(&topic.slug).is_ok());
    assert!(store.load::<RuleTopic>(&moved).is_err());
    app::reorganize_restore(&store, &text, true).unwrap();
    assert!(store.load::<RuleTopic>(&moved).is_ok());
    assert!(
        app::reorganize_restore(&store, "{}", true)
            .unwrap_err()
            .0
            .contains("Recibo de reorganização inválido")
    );
}

#[test]
fn base64_compativel_com_data_do_swift() {
    for (raw, encoded) in [
        (&b""[..], ""),
        (b"f", "Zg=="),
        (b"fo", "Zm8="),
        (b"foo", "Zm9v"),
        (b"foob", "Zm9vYg=="),
        (&[0xff, 0xfe, 0x00][..], "//4A"),
    ] {
        assert_eq!(reorganize::decode_base64(encoded).unwrap(), raw);
    }
    assert!(reorganize::decode_base64("Zg=x").is_none());
    assert!(reorganize::decode_base64("Z").is_none());
}
