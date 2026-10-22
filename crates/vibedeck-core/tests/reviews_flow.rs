//! Revisões: grupos, itens, kinds, prefixos de id e o gate de conclusão.

use vibedeck_core::Store;
use vibedeck_core::error::Error;
use vibedeck_core::model::*;
use vibedeck_core::reviews::gate;
use vibedeck_core::reviews::{self, ItemUpdate, NewItem, ReviewError};
use vibedeck_core::rules::{self, RuleExt};

fn fresh() -> (tempfile::TempDir, Store) {
    let tmp = tempfile::tempdir().unwrap();
    let store = Store::init(tmp.path(), "demo", None).unwrap();
    (tmp, store)
}

fn new_item(kind: &str, title: &str) -> NewItem {
    NewItem {
        kind: kind.into(),
        title: title.into(),
        details: None,
        priority: ReviewPriority::Normal,
        target: ReviewTarget::default(),
        rules: vec![],
        author: Author::Human,
    }
}

fn script_rule(text: &str) -> Rule {
    let mut r = Rule::new(text);
    r.test = Some(RuleTest {
        mode: RuleTestMode::Script,
        command: Some("true".into()),
        reason: None,
        rule_hash: r.content_hash(),
        generated_at: Timestamp::now(),
    });
    r
}

fn topic(store: &Store, slug: &str, paths: &[&str], rules: Vec<Rule>) {
    let mut t = RuleTopic::new(slug);
    t.paths = paths.iter().map(|s| s.to_string()).collect();
    t.rules = rules;
    store.save_rule_topic(slug, &t).unwrap();
}

fn check(item: Option<Id>, passed: bool, answered: &[&Rule], failures: &[&str]) -> RuleCheck {
    RuleCheck {
        schema: None,
        id: Id::new(),
        task: "t".into(),
        files: vec![],
        topics: vec![],
        review_item: item,
        results: answered
            .iter()
            .map(|r| RuleResult {
                topic: "x".into(),
                rule_id: r.id,
                verdict: RuleVerdict::Pass,
                note: None,
                source: RuleResultSource::Agent,
                exit_code: None,
            })
            .collect(),
        passed,
        warnings: vec![],
        failures: failures.iter().map(|s| s.to_string()).collect(),
        pending: vec![],
        author: Author::Ai,
        created_at: TimestampMs::now(),
    }
}

#[test]
fn grupo_criado_na_hora_e_busca_por_prefixo() {
    let (_t, store) = fresh();
    let (slug, a) = reviews::add_item(
        &store,
        new_item("disable", "Inativar botão"),
        "Tela de Login",
    )
    .unwrap();
    assert_eq!(slug, "tela-de-login");
    let (slug2, _) =
        reviews::add_item(&store, new_item("hide", "Ocultar banner"), "tela de login").unwrap();
    assert_eq!(slug2, "tela-de-login", "resolve por título sem criar outro");
    let g: ReviewGroup = store.load("tela-de-login").unwrap();
    assert_eq!(g.items.len(), 2);
    assert_eq!(g.title, "Tela de Login");
    assert_eq!(reviews::open_count(&g), 2);

    let id = a.id.to_string();
    let (s, _, i) = reviews::find_item(&store, &id[..8].to_lowercase()).unwrap();
    assert_eq!((s.as_str(), i), ("tela-de-login", 0));
    assert!(matches!(
        reviews::find_item(&store, &id[..3]),
        Err(Error::ItemNotFound(_))
    ));
    assert!(matches!(
        reviews::find_item(&store, "ffffffff"),
        Err(Error::ItemNotFound(_))
    ));
}

#[test]
fn grupo_com_barra_vira_subpasta() {
    let (_t, store) = fresh();
    let (slug, _) = reviews::add_item(&store, new_item("note", "x"), "app/Login").unwrap();
    assert_eq!(slug, "app/login");
    let rows = reviews::group_rows(&store).unwrap();
    assert_eq!(rows[0].group, "app");
    assert_eq!(rows[0].slug, "app/login");
}

#[test]
fn kind_desconhecido_e_alvo_vazio() {
    let (_t, store) = fresh();
    let err = reviews::add_item(&store, new_item("zzz", "x"), "g").unwrap_err();
    assert_eq!(
        err.to_string(),
        "Kind desconhecido 'zzz'. Disponíveis: disable, hide, fix, change, remove, note"
    );
    assert!(err.is_invalid_params());
    assert!(
        reviews::list_groups(&store).unwrap().is_empty(),
        "nada gravado"
    );
    let (_, item) = reviews::add_item(&store, new_item("fix", "sem alvo"), "g").unwrap();
    assert!(item.target.is_none());
}

#[test]
fn regras_resolvidas_para_slug_de_topico() {
    let (_t, store) = fresh();
    topic(&store, "api", &["src/api/**"], vec![]);
    let mut n = new_item("fix", "x");
    n.rules = vec!["API".into()];
    let (_, item) = reviews::add_item(&store, n, "g").unwrap();
    assert_eq!(item.rules, ["api"]);
    let mut n = new_item("fix", "y");
    n.rules = vec!["inexistente".into()];
    assert!(matches!(
        reviews::add_item(&store, n, "g"),
        Err(ReviewError::Core(Error::TopicNotFound(_)))
    ));
}

#[test]
fn update_carimba_data_e_status_invalido_nao_grava() {
    let (_t, store) = fresh();
    let (_, item) = reviews::add_item(&store, new_item("fix", "x"), "g").unwrap();
    let id = item.id.to_string();
    let err = reviews::apply_update(
        &store,
        &id,
        ItemUpdate {
            status: Some("feito".into()),
            title: Some("novo".into()),
            ..Default::default()
        },
    )
    .unwrap_err();
    assert_eq!(err.to_string(), "Status inválido: feito");
    let g: ReviewGroup = store.load("g").unwrap();
    assert_eq!(g.items[0].title, "x");

    let up = reviews::apply_update(
        &store,
        &id[..6],
        ItemUpdate {
            status: Some("in_progress".into()),
            priority: Some(ReviewPriority::High),
            title: Some("novo".into()),
            details: Some("d".into()),
            kind: Some("change".into()),
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(up.status, ReviewStatus::InProgress);
    assert_eq!(up.kind, "change");
    assert!(up.updated_at >= up.created_at);
    let err = reviews::apply_update(
        &store,
        &id,
        ItemUpdate {
            kind: Some("zzz".into()),
            ..Default::default()
        },
    )
    .unwrap_err();
    assert!(matches!(err, ReviewError::UnknownKind { .. }));
}

#[test]
fn remover_item() {
    let (_t, store) = fresh();
    let (_, item) = reviews::add_item(&store, new_item("fix", "x"), "g").unwrap();
    reviews::delete_item(&store, &item.id.to_string()).unwrap();
    let g: ReviewGroup = store.load("g").unwrap();
    assert!(g.items.is_empty());
    assert!(reviews::delete_item(&store, &item.id.to_string()).is_err());
}

#[test]
fn gate_item_livre_sem_regras() {
    let (_t, store) = fresh();
    let mut n = new_item("fix", "Livre");
    n.target.file = Some("README.md".into());
    let (_, item) = reviews::add_item(&store, n, "G").unwrap();
    // Sem tópicos nenhum: nada a verificar.
    gate::ensure_verified(&store, &item.id.to_string()).unwrap();
    let done = reviews::apply_update(
        &store,
        &item.id.to_string(),
        ItemUpdate {
            status: Some("done".into()),
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(done.status, ReviewStatus::Done);
    let g: ReviewGroup = store.load("g").unwrap();
    assert_eq!(reviews::open_count(&g), 0);
}

#[test]
fn gate_por_paths_do_topico() {
    let (_t, store) = fresh();
    let rule = script_rule("sidebar segue o padrão");
    topic(&store, "ui", &["Sources/App/**"], vec![rule.clone()]);

    let mut n = new_item("fix", "Sidebar");
    n.target.file = Some("Sources/App/Side.swift".into());
    let (_, item) = reviews::add_item(&store, n, "G").unwrap();
    let r = item.id.to_string();

    let e = gate::ensure_verified(&store, &r).unwrap_err();
    let msg = e.to_string();
    assert!(msg.starts_with("O item não pode ser concluído sem passar pelas regras:\n- Nenhum check registrado para este item (tópicos: ui)."));
    assert!(msg.ends_with(
        "\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item."
    ));
    // Fora do escopo dos paths: livre.
    let mut other = new_item("fix", "Outro");
    other.target.file = Some("docs/readme.md".into());
    let (_, other) = reviews::add_item(&store, other, "G").unwrap();
    gate::ensure_verified(&store, &other.id.to_string()).unwrap();

    // check reprovado
    store
        .save_check(&check(Some(item.id), false, &[], &["regra X"]))
        .unwrap();
    let problems = rules::verification_problems(&store, &item_of(&store, &r)).unwrap();
    assert_eq!(problems, ["Falhou no último check: regra X"]);

    // check aprovado e posterior
    std::thread::sleep(std::time::Duration::from_millis(5));
    store
        .save_check(&check(Some(item.id), true, &[&rule], &[]))
        .unwrap();
    gate::ensure_verified(&store, &r).unwrap();

    // check de OUTRO item não vale
    let (_, third) = {
        let mut n = new_item("fix", "Terceiro");
        n.target.file = Some("Sources/App/Third.swift".into());
        reviews::add_item(&store, n, "G").unwrap()
    };
    assert!(gate::ensure_verified(&store, &third.id.to_string()).is_err());

    // done via update respeita o gate; --force passa
    let err = reviews::apply_update(
        &store,
        &third.id.to_string(),
        ItemUpdate {
            status: Some("done".into()),
            ..Default::default()
        },
    )
    .unwrap_err();
    assert!(matches!(err, ReviewError::RulesNotVerified(_)));
    let g: ReviewGroup = store.load("g").unwrap();
    assert!(g.items.iter().find(|i| i.id == third.id).unwrap().status == ReviewStatus::Open);
    reviews::apply_update(
        &store,
        &third.id.to_string(),
        ItemUpdate {
            status: Some("done".into()),
            force: true,
            ..Default::default()
        },
    )
    .unwrap();
}

fn item_of(store: &Store, r: &str) -> ReviewItem {
    let (_, g, i) = reviews::find_item(store, r).unwrap();
    g.items[i].clone()
}

#[test]
fn gate_regra_nova_e_manual_must() {
    let (_t, store) = fresh();
    let scripted = script_rule("roda script");
    let mut manual = Rule::new("inspeção manual");
    manual.severity = RuleSeverity::Must;
    let mut manual_should = Rule::new("opcional");
    manual_should.severity = RuleSeverity::Should;
    topic(
        &store,
        "geral",
        &[],
        vec![scripted.clone(), manual.clone(), manual_should.clone()],
    );
    let (_, item) = reviews::add_item(&store, new_item("fix", "x"), "g").unwrap();
    let r = item.id.to_string();

    // Check aprovado que respondeu só o script: falta a manual obrigatória (a should não segura).
    store
        .save_check(&check(Some(item.id), true, &[&scripted], &[]))
        .unwrap();
    let problems = rules::verification_problems(&store, &item_of(&store, &r)).unwrap();
    assert_eq!(
        problems,
        [
            "Regra manual obrigatória sem verificação: [geral] inspeção manual (envie o check com as regras manuais respondidas)"
        ]
    );

    // Responder a manual libera.
    std::thread::sleep(std::time::Duration::from_millis(5));
    store
        .save_check(&check(Some(item.id), true, &[&scripted, &manual], &[]))
        .unwrap();
    assert!(
        rules::verification_problems(&store, &item_of(&store, &r))
            .unwrap()
            .is_empty()
    );

    // Regra de script nova depois do check: "Regra nova desde o último check".
    let newer = script_rule("script novo");
    let mut t: RuleTopic = store.load("geral").unwrap();
    t.rules.push(newer);
    store.save_rule_topic("geral", &t).unwrap();
    let problems = rules::verification_problems(&store, &item_of(&store, &r)).unwrap();
    assert_eq!(
        problems,
        ["Regra nova desde o último check: [geral] script novo"]
    );
}

#[test]
fn gate_regras_explicitas_do_item() {
    let (_t, store) = fresh();
    let rule = script_rule("api ok");
    topic(&store, "api", &["src/api/**"], vec![rule.clone()]);
    let mut n = new_item("fix", "Endpoint");
    n.rules = vec!["api".into()];
    let (_, item) = reviews::add_item(&store, n, "G").unwrap();
    assert!(gate::ensure_verified(&store, &item.id.to_string()).is_err());
    store
        .save_check(&check(Some(item.id), true, &[&rule], &[]))
        .unwrap();
    gate::ensure_verified(&store, &item.id.to_string()).unwrap();
}

#[test]
fn update_com_regras_grava_antes_do_gate() {
    let (_t, store) = fresh();
    topic(&store, "api", &["src/api/**"], vec![script_rule("api ok")]);
    let (_, item) = reviews::add_item(&store, new_item("fix", "x"), "g").unwrap();
    let err = reviews::apply_update(
        &store,
        &item.id.to_string(),
        ItemUpdate {
            rules: Some(vec!["api".into()]),
            status: Some("done".into()),
            ..Default::default()
        },
    )
    .unwrap_err();
    assert!(matches!(err, ReviewError::RulesNotVerified(_)));
    let g: ReviewGroup = store.load("g").unwrap();
    assert_eq!(g.items[0].rules, ["api"], "write parcial, como no Swift");
    assert_eq!(g.items[0].status, ReviewStatus::Open);
}

#[test]
fn listagem_filtrada() {
    let (_t, store) = fresh();
    reviews::add_item(&store, new_item("fix", "a"), "g1").unwrap();
    let (_, b) = reviews::add_item(&store, new_item("note", "b"), "g1").unwrap();
    reviews::add_item(&store, new_item("fix", "c"), "g2").unwrap();
    reviews::apply_update(
        &store,
        &b.id.to_string(),
        ItemUpdate {
            status: Some("wontfix".into()),
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(
        reviews::list_items(&store, None, None, None).unwrap().len(),
        3
    );
    assert_eq!(
        reviews::list_items(&store, Some("g1"), None, None)
            .unwrap()
            .len(),
        2
    );
    assert_eq!(
        reviews::list_items(&store, None, Some(ReviewStatus::Wontfix), None)
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        reviews::list_items(&store, None, None, Some("fix"))
            .unwrap()
            .len(),
        2
    );
    assert!(matches!(
        reviews::list_items(&store, Some("nada"), None, None),
        Err(Error::GroupNotFound(_))
    ));
    let rows = reviews::group_rows(&store).unwrap();
    assert_eq!((rows[0].open, rows[0].total), (1, 2));
}
