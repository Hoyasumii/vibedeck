//! Workflows: CRUD, etapas, transições, plano (porta de `WorkflowsTests.swift`).

use tempfile::TempDir;
use vibedeck_core::model::*;
use vibedeck_core::workflows::*;
use vibedeck_core::{Error, Store};

fn store() -> (TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "teste", None).unwrap();
    (dir, store)
}

fn agent(store: &Store, title: &str) -> String {
    store.create(&Agent::new(title), None).unwrap().slug
}

fn command(store: &Store, title: &str) -> String {
    store.create(&Command::new(title), None).unwrap().slug
}

fn wf_new(store: &Store, title: &str) -> String {
    create_workflow(store, title, None, None, None, vec![], Author::Human)
        .unwrap()
        .slug
}

fn add_step(store: &Store, wf: &str, target: &str) -> String {
    add_workflow_step(store, wf, NextStepKind::Agent, target, None)
        .unwrap()
        .1
}

#[test]
fn crud_e_resolucao() {
    let (_d, store) = store();
    let rec = create_workflow(
        &store,
        "Revisão de PR",
        Some("Revisa até passar".into()),
        Some("<número do PR>".into()),
        None,
        vec![],
        Author::Ai,
    )
    .unwrap();
    assert_eq!(rec.slug, "revisao-de-pr");
    assert_eq!(rec.value.author, Author::Ai);
    assert_eq!(
        rec.value.schema.as_deref(),
        Some("https://vibedeck-schema.alanreisanjo.workers.dev/v1/workflow.schema.json")
    );
    let prefix = rec.value.id.to_string()[..6].to_string();
    assert_eq!(
        resolve_workflow_slug(&store, &prefix).unwrap(),
        "revisao-de-pr"
    );
    assert_eq!(
        resolve_workflow_slug(&store, "Revisão de PR").unwrap(),
        "revisao-de-pr"
    );
    update_workflow(&store, "revisao-de-pr", |w| {
        w.max_steps = Some(10);
        Ok(())
    })
    .unwrap();
    assert_eq!(
        load_workflow(&store, "revisao-de-pr").unwrap().max_steps,
        Some(10)
    );
    assert_eq!(list_workflows(&store).unwrap().len(), 1);
    delete_workflow(&store, "revisao-de-pr").unwrap();
    assert!(matches!(
        load_workflow(&store, "revisao-de-pr"),
        Err(WorkflowError::Core(Error::WorkflowNotFound(_)))
    ));
    assert!(matches!(
        create_workflow(&store, "   ", None, None, None, vec![], Author::Human),
        Err(WorkflowError::Core(Error::InvalidName))
    ));
}

#[test]
fn decode_tolerante_e_omite_vazios() {
    let (_d, store) = store();
    std::fs::create_dir_all(store.dir::<Workflow>()).unwrap();
    std::fs::write(
        store.dir::<Workflow>().join("minimo.json"),
        r#"{"title":"Mínimo","steps":[{"ref":"revisor","transitions":[{"when":"  ","to":"revisor"}]}]}"#,
    )
    .unwrap();
    let w = load_workflow(&store, "minimo").unwrap();
    assert_eq!(w.author, Author::Human);
    assert!(w.max_steps.is_none() && w.summary.is_none());
    let mut step = WorkflowStep::new("revisor", NextStepKind::Agent, "revisor");
    step.transitions = vec![WorkflowTransition::new(None, None, "revisor")];
    assert_eq!(w.steps, vec![step]);
    let text =
        String::from_utf8(vibedeck_core::json::encode(&Workflow::new("Vazio")).unwrap()).unwrap();
    for k in ["steps", "tags", "maxSteps", "input"] {
        assert!(!text.contains(k), "{k} não deveria ser gravado");
    }
}

#[test]
fn etapas_validam_e_ganham_ids_unicos() {
    let (_d, store) = store();
    let w = wf_new(&store, "Fluxo");
    let a = agent(&store, "Revisor");
    let c = command(&store, "Commit");
    assert_eq!(add_step(&store, &w, &a), "revisor");
    assert_eq!(add_step(&store, &w, "Revisor"), "revisor-2");
    let (rec, id) =
        add_workflow_step(&store, &w, NextStepKind::Command, &c, Some("  feat: x ")).unwrap();
    assert_eq!(id, "commit");
    let last = rec.value.steps.last().unwrap();
    assert_eq!(last.note.as_deref(), Some("feat: x"));
    assert_eq!(last.r#ref, c);
    let err = add_workflow_step(&store, &w, NextStepKind::Skill, "nao-existe", None).unwrap_err();
    assert!(matches!(err, WorkflowError::Core(Error::SkillNotFound(s)) if s == "nao-existe"));
    let rec = move_workflow_step(&store, &w, "commit", 1).unwrap();
    let ids: Vec<_> = rec.value.steps.iter().map(|s| s.id.as_str()).collect();
    assert_eq!(ids, ["commit", "revisor", "revisor-2"]);
    // posição fora da faixa é limitada
    let rec = move_workflow_step(&store, &w, "commit", 99).unwrap();
    assert_eq!(rec.value.steps.last().unwrap().id, "commit");
}

#[test]
fn transicoes_permitem_laco_e_mantem_senao_por_ultimo() {
    let (_d, store) = store();
    let w = wf_new(&store, "Fluxo");
    let a = agent(&store, "Autor");
    let r = agent(&store, "Revisor");
    add_step(&store, &w, &a);
    add_step(&store, &w, &r);
    add_workflow_transition(&store, &w, "autor", "revisor", None, None).unwrap();
    add_workflow_transition(
        &store,
        &w,
        "revisor",
        "autor",
        Some("encontrou problemas"),
        None,
    )
    .unwrap();
    add_workflow_transition(&store, &w, "revisor", "2", None, None).unwrap();
    add_workflow_transition(&store, &w, "revisor", "autor", Some("faltam testes"), None).unwrap();
    let review = load_workflow(&store, &w).unwrap().steps[1].clone();
    let whens: Vec<_> = review.transitions.iter().map(|t| t.when.clone()).collect();
    assert_eq!(
        whens,
        [
            Some("encontrou problemas".to_string()),
            Some("faltam testes".to_string()),
            None
        ]
    );
    // segundo "senão" e destino inexistente falham
    assert!(add_workflow_transition(&store, &w, "revisor", "autor", None, None).is_err());
    assert!(add_workflow_transition(&store, &w, "revisor", "nao-existe", None, None).is_err());
    remove_workflow_transition(&store, &w, "revisor", 2).unwrap();
    assert_eq!(
        load_workflow(&store, &w).unwrap().steps[1]
            .transitions
            .len(),
        2
    );
    assert!(remove_workflow_transition(&store, &w, "revisor", 5).is_err());
    assert!(remove_workflow_transition(&store, &w, "revisor", 0).is_err());
    // remover etapa derruba as transições para ela
    remove_workflow_step(&store, &w, "autor").unwrap();
    let left = load_workflow(&store, &w).unwrap().steps;
    assert_eq!(left.len(), 1);
    assert_eq!(
        left[0].transitions,
        vec![WorkflowTransition::new(None, None, "revisor")]
    );
}

#[test]
fn max_visits_limpa_com_zero() {
    let (_d, store) = store();
    let w = wf_new(&store, "Fluxo");
    let a = agent(&store, "Autor");
    add_step(&store, &w, &a);
    let rec = set_workflow_step_max_visits(&store, &w, "autor", Some(3)).unwrap();
    assert_eq!(rec.value.steps[0].max_visits, Some(3));
    let rec = set_workflow_step_max_visits(&store, &w, "1", Some(0)).unwrap();
    assert_eq!(rec.value.steps[0].max_visits, None);
}

#[test]
fn plano_resolve_nos_e_avisa() {
    let (_d, store) = store();
    let mut ag = Agent::new("Revisor");
    ag.model = Some("opus".into());
    ag.prompt = "Revise.".into();
    let a = store.create(&ag, None).unwrap().slug;
    let mut cm = Command::new("Commit");
    cm.argument_hint = Some("<mensagem>".into());
    cm.prompt = "Commite $ARGUMENTS".into();
    let c = store.create(&cm, None).unwrap().slug;
    let w = create_workflow(
        &store,
        "Fluxo",
        None,
        Some("<PR>".into()),
        None,
        vec![],
        Author::Human,
    )
    .unwrap()
    .slug;
    add_step(&store, &w, &a);
    add_workflow_step(&store, &w, NextStepKind::Command, &c, None).unwrap();
    add_workflow_transition(&store, &w, "revisor", "commit", Some("aprovado"), None).unwrap();
    update_workflow(&store, &w, |wf| {
        let mut s = WorkflowStep::new("sumiu", NextStepKind::Skill, "sumiu");
        s.transitions = vec![WorkflowTransition::new(None, None, "fantasma")];
        wf.steps.push(s);
        Ok(())
    })
    .unwrap();
    let plan = workflow_plan(&store, &w, Some("PR 12")).unwrap();
    assert_eq!(plan.start.as_deref(), Some("revisor"));
    assert_eq!(plan.input.as_deref(), Some("PR 12"));
    assert_eq!(plan.max_steps, DEFAULT_MAX_STEPS);
    assert_eq!(plan.steps[0].title.as_deref(), Some("Revisor"));
    assert_eq!(plan.steps[0].model.as_deref(), Some("opus"));
    assert_eq!(plan.steps[0].prompt.as_deref(), Some("Revise."));
    assert_eq!(plan.steps[1].argument_hint.as_deref(), Some("<mensagem>"));
    assert!(plan.steps[1].transitions.is_none());
    assert_eq!(
        plan.steps[2].warnings.as_deref().unwrap(),
        [
            "Skill não encontrada: sumiu",
            "Transição para etapa inexistente: fantasma"
        ]
    );
    assert_eq!(plan.all_warnings().len(), 2);
    assert!(plan.warnings.is_none());
    assert_eq!(plan.input_hint.as_deref(), Some("<PR>"));
    assert!(workflow_plan(&store, &w, None).unwrap().input.is_none());
    let json = plan.json().unwrap();
    assert!(json.contains("\"start\" : \"revisor\"") && !json.contains("\"nextSteps\" :"));
    assert!(!json.ends_with('\n'));
    assert!(
        plan.prompt()
            .unwrap()
            .starts_with("Execute o workflow \"Fluxo\" do VibeDeck")
    );
    let empty = WorkflowPlan::build("x", &Workflow::new("X"), None, &[], &[], &[]);
    assert!(empty.start.is_none());
    assert_eq!(
        empty.warnings.as_deref().unwrap(),
        ["O workflow não tem etapas."]
    );
}

#[test]
fn veredito_ignora_caixa_acento_e_marcacao() {
    let t = WorkflowTransition::new(Some("VIÁVEL".into()), None, "x");
    assert!(t.matches("viavel"));
    assert!(t.matches(" `VIÁVEL`. "));
    assert!(!t.matches("INVIÁVEL"));
    assert!(!WorkflowTransition::new(None, Some("ok".into()), "x").matches("ok"));
    assert!(WorkflowTransition::new(None, None, "x").is_fallback() && !t.is_fallback());
    assert_eq!(t.label(), "= VIÁVEL");
    assert_eq!(
        WorkflowTransition::new(None, Some("achou".into()), "x").label(),
        "se achou"
    );
    assert_eq!(WorkflowTransition::new(None, None, "x").label(), "senão");
}
