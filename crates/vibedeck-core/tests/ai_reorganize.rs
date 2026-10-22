//! Reorganização com IA: portado de `ReorganizeDiscoverTests.swift`.

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::PathBuf;

use serde_json::{Value, json};
use vibedeck_core::ai::AiError;
use vibedeck_core::ai::reorganize::{
    self, Acceptance, Action, Answer, Concept, Kind, Lease, Proposal, Reference,
};
use vibedeck_core::json;
use vibedeck_core::model::{Author, ReviewGroup, ReviewItem, ReviewStatus, Rule, RuleTopic};
use vibedeck_core::slug;
use vibedeck_core::{Record, Store};

struct Fixture {
    _dir: tempfile::TempDir,
    store: Store,
}

fn fixture() -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "Projeto", None).unwrap();
    Fixture { _dir: dir, store }
}

impl Fixture {
    fn root(&self) -> PathBuf {
        self.store.root().to_path_buf()
    }

    fn topic(&self, title: &str) -> Record<RuleTopic> {
        self.store.create(&RuleTopic::new(title), None).unwrap()
    }

    fn doc(&self, title: &str, body: &str) -> String {
        let slug = slug::make(title);
        let path = self.doc_path(&slug);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, format!("# {title}\n\n{body}\n")).unwrap();
        slug
    }

    fn doc_path(&self, slug: &str) -> PathBuf {
        self.store
            .data_dir()
            .join("docs")
            .join(format!("{slug}.md"))
    }

    fn read_doc(&self, slug: &str) -> String {
        fs::read_to_string(self.doc_path(slug)).unwrap()
    }

    fn idea(&self, title: &str) -> String {
        self.store
            .create_idea(title, None, &[], Author::Human, None)
            .unwrap()
            .slug
    }

    fn group(&self, title: &str) -> Record<ReviewGroup> {
        self.store.create(&ReviewGroup::new(title), None).unwrap()
    }

    fn proposal(&self, actions: Vec<Action>) -> Proposal {
        let data = json::encode(&Answer { actions }).unwrap();
        reorganize::parse(
            &data,
            &self.store,
            &reorganize::fingerprint(&self.store).unwrap(),
        )
        .unwrap()
    }

    fn apply_all(&self, p: &Proposal) -> reorganize::Receipt {
        let ids = p.actions.iter().map(|a| a.id.clone()).collect();
        reorganize::apply(
            &self.store,
            p,
            &Acceptance {
                selected: ids,
                conflicts: BTreeMap::new(),
            },
        )
        .unwrap()
    }
}

fn act(kind: Kind, item: Reference, reason: &str) -> Action {
    Action::new(kind, item, reason)
}

fn moved(item: Reference, reason: &str, destination: &str) -> Action {
    Action {
        destination: Some(destination.into()),
        ..act(Kind::Move, item, reason)
    }
}

fn accept(ids: &[&str]) -> Acceptance {
    Acceptance {
        selected: ids.iter().map(|s| s.to_string()).collect(),
        conflicts: BTreeMap::new(),
    }
}

#[test]
fn todos_os_conceitos_e_referencias_invalidas_nunca_gravam() {
    let f = fixture();
    let topic = f.topic("Regras");
    let doc = f.doc("Docs", "");
    let idea = f.idea("Ideia");
    let group = f.group("Revisões");
    let refs = [
        (Concept::Rules, topic.slug),
        (Concept::Docs, doc),
        (Concept::Ideas, idea),
        (Concept::Reviews, group.slug),
    ];
    let mut actions: Vec<Action> = refs
        .iter()
        .map(|(c, s)| {
            moved(
                Reference::new(*c, s),
                &format!("Agrupar item citado: {s}"),
                "grupo",
            )
        })
        .collect();
    let fp = reorganize::fingerprint(&f.store).unwrap();
    actions.push(moved(
        Reference::new(Concept::Docs, "inexistente"),
        "Inválido",
        "grupo",
    ));
    let result = f.proposal(actions);
    assert_eq!(result.actions.len(), 4);
    assert_eq!(result.discarded, 1);
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), fp);
    for invalid in ["not json", "{}", "{\"actions\":null}"] {
        let e = reorganize::parse(invalid.as_bytes(), &f.store, &fp).unwrap_err();
        assert!(matches!(e, AiError::ReorganizeInvalidJson), "{invalid}");
    }
    assert!(
        AiError::ReorganizeInvalidJson
            .to_string()
            .contains("Nenhum arquivo")
    );
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), fp);
}

#[test]
fn mesclar_une_campos_preserva_desconhecidos_e_desfaz() {
    let f = fixture();
    let mut first_rule = Rule::new("Primeira");
    first_rule.author = Author::Human;
    let second_rule = Rule::new("Segunda");
    let mut left = RuleTopic::new("Mantido");
    left.description = Some("Primeira descrição".into());
    left.tags = vec!["a".into()];
    left.paths = vec!["Sources/**".into()];
    left.rules = vec![first_rule.clone()];
    let left = f.store.create(&left, None).unwrap();
    let mut right = RuleTopic::new("Repetido");
    right.description = Some("Outra descrição".into());
    right.tags = vec!["b".into()];
    right.paths = vec!["Tests/**".into()];
    right.rules = vec![second_rule.clone()];
    let right = f.store.create(&right, None).unwrap();
    let right_file = f
        .store
        .data_dir()
        .join(format!("rules/{}.json", right.slug));
    let mut raw: Value = serde_json::from_slice(&fs::read(&right_file).unwrap()).unwrap();
    raw["custom"] = json!({"preservar": true});
    fs::write(&right_file, json::to_vdjson(&raw)).unwrap();
    let left_file = f.store.data_dir().join(format!("rules/{}.json", left.slug));
    let (before_left, before_right) = (
        fs::read(&left_file).unwrap(),
        fs::read(&right_file).unwrap(),
    );

    let mut action = act(
        Kind::Merge,
        Reference::new(Concept::Rules, &left.slug),
        "Mesclar ambos",
    );
    action.involved = vec![Reference::new(Concept::Rules, &right.slug)];
    let p = f.proposal(vec![action.clone()]);
    let receipt = reorganize::apply(&f.store, &p, &accept(&[action.id.as_str()])).unwrap();
    let merged: RuleTopic = f.store.load(&left.slug).unwrap();
    assert_eq!(
        merged.tags.iter().collect::<HashSet<_>>(),
        HashSet::from([&"a".to_string(), &"b".to_string()])
    );
    assert_eq!(merged.paths.len(), 2);
    assert_eq!(
        merged.rules.iter().map(|r| r.id).collect::<HashSet<_>>(),
        HashSet::from([first_rule.id, second_rule.id])
    );
    assert_eq!(merged.id, left.value.id);
    let raw: Value = serde_json::from_slice(&fs::read(&left_file).unwrap()).unwrap();
    assert_eq!(raw["custom"]["preservar"], true);
    assert!(merged.description.unwrap().contains("Outra descrição"));
    assert_eq!(f.store.rule_topics().unwrap().len(), 1);
    // o repetido foi arquivado, nunca apagado
    assert!(
        receipt
            .after
            .keys()
            .any(|k| k.starts_with(".vibedeck/archive/reorganize/"))
    );

    reorganize::restore(&f.store, &receipt, false).unwrap();
    assert_eq!(fs::read(&left_file).unwrap(), before_left);
    assert_eq!(fs::read(&right_file).unwrap(), before_right);
    reorganize::restore(&f.store, &receipt, true).unwrap();
    assert_eq!(f.store.rule_topics().unwrap().len(), 1);
}

#[test]
fn conflito_exige_escolha_explicita_e_arquiva_os_bytes_originais() {
    let f = fixture();
    let a = f.doc("A", "Escolha A");
    let b = f.doc("B", "Escolha B");
    let original = fs::read(f.doc_path(&b)).unwrap();
    let mut action = act(
        Kind::Conflict,
        Reference::new(Concept::Docs, &a),
        "A contradiz B",
    );
    action.involved = vec![Reference::new(Concept::Docs, &b)];
    let p = f.proposal(vec![action.clone()]);

    let empty = reorganize::apply(&f.store, &p, &accept(&[&action.id])).unwrap();
    assert!(empty.before.is_empty() && empty.after.is_empty());
    assert!(f.doc_path(&a).exists() && f.doc_path(&b).exists());

    let mut bad = accept(&[&action.id]);
    bad.conflicts
        .insert(action.id.clone(), "inexistente".into());
    assert!(matches!(
        reorganize::apply(&f.store, &p, &bad),
        Err(AiError::ReorganizeInvalidAction)
    ));

    let mut good = accept(&[&action.id]);
    good.conflicts.insert(action.id.clone(), action.item.key());
    let receipt = reorganize::apply(&f.store, &p, &good).unwrap();
    let archived = receipt
        .after
        .iter()
        .find(|(k, _)| k.starts_with(".vibedeck/archive/"))
        .unwrap();
    assert_eq!(archived.1, &original);
    assert!(f.doc_path(&a).exists() && !f.doc_path(&b).exists());
    reorganize::restore(&f.store, &receipt, false).unwrap();
    assert_eq!(fs::read(f.doc_path(&b)).unwrap(), original);
}

#[test]
fn mover_topico_preserva_referencias_promocoes_e_checks_historicos() {
    let f = fixture();
    let idea = f.idea("Promovida");
    let promoted = f.store.promote_idea(&idea, &HashSet::new()).unwrap();
    let topic: RuleTopic = f.store.load(&promoted).unwrap();
    let mut group = ReviewGroup::new("Área");
    let mut item = ReviewItem::new("note", "Revisão");
    item.rules = vec![promoted.clone()];
    group.items.push(item);
    let group = f.store.create(&group, None).unwrap();
    let check_file = f.store.checks_dir().join("historico.json");
    let check = format!("{{\"topic\":\"{promoted}\"}}");
    fs::write(&check_file, &check).unwrap();
    let doc = f.doc(
        "Referências",
        &format!("[Tópico](../rules/{promoted}.json)"),
    );

    let action = moved(
        Reference::new(Concept::Rules, &promoted),
        "Mover tópico citado",
        "especifico",
    );
    let p = f.proposal(vec![action.clone()]);
    let receipt = f.apply_all(&p);
    let target = format!("especifico/{promoted}");
    assert_eq!(
        f.store.resolve::<RuleTopic>(&topic.id.to_string()).unwrap(),
        target
    );
    let reloaded: vibedeck_core::model::Idea = f.store.load(&idea).unwrap();
    assert_eq!(reloaded.promoted_topic.as_deref(), Some(target.as_str()));
    let g: ReviewGroup = f.store.load(&group.slug).unwrap();
    assert_eq!(g.items[0].rules, vec![target.clone()]);
    assert!(
        f.read_doc(&doc)
            .contains(&format!("../rules/{target}.json"))
    );
    assert_eq!(fs::read_to_string(&check_file).unwrap(), check);
    let slugs: Vec<String> = f
        .store
        .rule_topics()
        .unwrap()
        .into_iter()
        .map(|r| r.slug)
        .collect();
    assert_eq!(slugs, vec![target]);

    reorganize::restore(&f.store, &receipt, false).unwrap();
    let reloaded: vibedeck_core::model::Idea = f.store.load(&idea).unwrap();
    assert_eq!(reloaded.promoted_topic.as_deref(), Some(promoted.as_str()));
}

#[test]
fn mover_doc_reescreve_links_de_entrada_e_saida_sem_mexer_na_prosa() {
    let f = fixture();
    let a = f.doc("A", "[B](b.md)\nProsa: b.md");
    f.doc("B", "[A](a.md#secao)");
    let action = moved(Reference::new(Concept::Docs, &a), "Mover A", "grupo");
    let p = f.proposal(vec![action]);
    f.apply_all(&p);
    let moved_doc = f.read_doc("grupo/a");
    assert!(moved_doc.contains("[B](../b.md)"), "{moved_doc}");
    assert!(moved_doc.contains("Prosa: b.md"));
    assert!(f.read_doc("b").contains("[A](grupo/a.md#secao)"));
}

#[test]
fn protegidos_e_incompativeis_rejeitam_o_lote_inteiro() {
    let f = fixture();
    let promoted = f.idea("Promovida");
    f.store.promote_idea(&promoted, &HashSet::new()).unwrap();
    let other = f.idea("Outra");
    let mut merge = act(
        Kind::Merge,
        Reference::new(Concept::Ideas, &other),
        "Inválida",
    );
    merge.involved = vec![Reference::new(Concept::Ideas, &promoted)];
    let flow = Action {
        title: Some("Melhoria".into()),
        content: Some("Corpo".into()),
        ..act(Kind::Flow, Reference::new(Concept::Ideas, &other), "Fluxo")
    };
    let p = f.proposal(vec![flow, merge]);
    let ids: Vec<String> = p.actions.iter().map(|a| a.id.clone()).collect();
    let e = reorganize::apply(
        &f.store,
        &p,
        &Acceptance {
            selected: ids,
            conflicts: BTreeMap::new(),
        },
    )
    .unwrap_err();
    assert!(matches!(e, AiError::ReorganizeIncompatible));
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), p.fingerprint);

    let mut closed = ReviewItem::new("note", "Encerrada");
    closed.status = ReviewStatus::Done;
    let open = ReviewItem::new("note", "Aberta");
    let mut group = ReviewGroup::new("Revisões");
    group.items = vec![closed.clone(), open.clone()];
    let group = f.store.create(&group, None).unwrap();
    let mut conflict = act(
        Kind::Conflict,
        Reference::with_item(Concept::Reviews, &group.slug, &closed.id.to_string()),
        "Contradição",
    );
    conflict.involved = vec![Reference::with_item(
        Concept::Reviews,
        &group.slug,
        &open.id.to_string(),
    )];
    let cp = f.proposal(vec![conflict.clone()]);
    let mut acceptance = accept(&[&conflict.id]);
    acceptance
        .conflicts
        .insert(conflict.id.clone(), conflict.involved[0].key());
    assert!(matches!(
        reorganize::apply(&f.store, &cp, &acceptance),
        Err(AiError::ReorganizeIncompatible)
    ));
    let g: ReviewGroup = f.store.load(&group.slug).unwrap();
    assert_eq!(g.items[0].status, ReviewStatus::Done);
}

#[test]
fn bloqueios_permitem_aceitar_o_resto_sem_gravar_na_verificacao() {
    let f = fixture();
    let promoted = f.idea("Promovida");
    f.store.promote_idea(&promoted, &HashSet::new()).unwrap();
    let other = f.idea("Outra");
    let mut blocked = act(
        Kind::Merge,
        Reference::new(Concept::Ideas, &other),
        "Mesclar",
    );
    blocked.involved = vec![Reference::new(Concept::Ideas, &promoted)];
    let flow = Action {
        title: Some("Melhoria".into()),
        content: Some("Corpo".into()),
        ..act(Kind::Flow, Reference::new(Concept::Ideas, &other), "Fluxo")
    };
    let p = f.proposal(vec![blocked.clone(), flow.clone()]);
    let all = Acceptance {
        selected: p.actions.iter().map(|a| a.id.clone()).collect(),
        conflicts: BTreeMap::new(),
    };
    let blockers = reorganize::blockers(&f.store, &p, &all).unwrap();
    assert_eq!(blockers.keys().collect::<Vec<_>>(), vec![&blocked.id]);
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), p.fingerprint);
    reorganize::apply(
        &f.store,
        &p,
        &Acceptance {
            selected: p
                .actions
                .iter()
                .map(|a| a.id.clone())
                .filter(|i| !blockers.contains_key(i))
                .collect(),
            conflicts: BTreeMap::new(),
        },
    )
    .unwrap();
    assert_eq!(f.store.ideas().unwrap().len(), 3);
    let kept: vibedeck_core::model::Idea = f.store.load(&promoted).unwrap();
    assert!(kept.promoted_topic.is_some());
}

#[test]
fn bloqueios_detectam_acoes_sobrepostas_e_destinos_ocupados() {
    let f = fixture();
    let doc = f.doc("Doc", "");
    let first = moved(Reference::new(Concept::Docs, &doc), "Primeiro", "grupo");
    let second = moved(Reference::new(Concept::Docs, &doc), "Segundo", "outro");
    let p = f.proposal(vec![first.clone(), second.clone()]);
    let b = reorganize::blockers(&f.store, &p, &accept(&[&first.id, &second.id])).unwrap();
    assert_eq!(b.keys().collect::<Vec<_>>(), vec![&second.id]);
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), p.fingerprint);

    fs::create_dir_all(f.store.data_dir().join("docs/ocupado")).unwrap();
    fs::write(
        f.store.data_dir().join("docs/ocupado/doc.md"),
        "# Existente",
    )
    .unwrap();
    let occupied = moved(Reference::new(Concept::Docs, &doc), "Ocupado", "ocupado");
    let op = f.proposal(vec![occupied.clone()]);
    let b = reorganize::blockers(&f.store, &op, &accept(&[&occupied.id])).unwrap();
    assert_eq!(b.keys().collect::<Vec<_>>(), vec![&occupied.id]);
    f.doc("Mudança", "");
    assert!(matches!(
        reorganize::blockers(&f.store, &op, &accept(&[&occupied.id])),
        Err(AiError::ReorganizeStale)
    ));
}

#[test]
fn fluxo_e_criacao_de_topico_usam_ia_e_slugs_unicos() {
    let f = fixture();
    let topic = f.topic("Tópico");
    let create = Action {
        destination: Some("grupo".into()),
        title: Some("Novo".into()),
        ..act(
            Kind::Create,
            Reference::new(Concept::Rules, &topic.slug),
            "Agrupar",
        )
    };
    let flow = Action {
        title: Some("Fluxo".into()),
        content: Some("Melhoria proposta".into()),
        ..act(
            Kind::Flow,
            Reference::new(Concept::Rules, &topic.slug),
            "Melhorar",
        )
    };
    for _ in 0..2 {
        // ids novos a cada rodada
        let mut c = create.clone();
        c.id = vibedeck_core::model::Id::new().to_string();
        let mut fl = flow.clone();
        fl.id = vibedeck_core::model::Id::new().to_string();
        let p = f.proposal(vec![c, fl]);
        f.apply_all(&p);
    }
    let topics: Vec<_> = f
        .store
        .rule_topics()
        .unwrap()
        .into_iter()
        .filter(|r| r.slug.starts_with("grupo/"))
        .collect();
    assert_eq!(topics.len(), 2);
    assert!(
        topics
            .iter()
            .all(|t| t.value.author == Author::Ai && t.value.rules.is_empty())
    );
    assert!(
        f.store
            .ideas()
            .unwrap()
            .iter()
            .all(|i| i.value.author == Author::Ai && i.value.promoted_topic.is_none())
    );
}

#[test]
fn obsoleto_colisao_travessia_e_desfazer_inseguro() {
    let f = fixture();
    let doc = f.doc("Doc", "");
    let action = moved(Reference::new(Concept::Docs, &doc), "Mover", "grupo");
    let p = f.proposal(vec![action.clone()]);
    fs::write(f.doc_path(&doc), "Alterado").unwrap();
    assert!(matches!(
        reorganize::apply(&f.store, &p, &accept(&[&action.id])),
        Err(AiError::ReorganizeStale)
    ));
    let unsafe_action = moved(Reference::new(Concept::Docs, &doc), "Inválido", "../fora");
    assert!(f.proposal(vec![unsafe_action]).actions.is_empty());

    fs::create_dir_all(f.doc_path("grupo/x").parent().unwrap()).unwrap();
    fs::write(f.doc_path(&format!("grupo/{doc}")), "Ocupado").unwrap();
    let occupied = f.proposal(vec![action.clone()]);
    assert!(matches!(
        reorganize::apply(&f.store, &occupied, &accept(&[&action.id])),
        Err(AiError::ReorganizeOccupied)
    ));
    assert_eq!(fs::read_to_string(f.doc_path(&doc)).unwrap(), "Alterado");

    fs::remove_file(f.doc_path(&format!("grupo/{doc}"))).unwrap();
    let again = f.proposal(vec![action.clone()]);
    let receipt = reorganize::apply(&f.store, &again, &accept(&[&action.id])).unwrap();
    fs::write(f.doc_path(&format!("grupo/{doc}")), "Edição posterior").unwrap();
    assert!(matches!(
        reorganize::restore(&f.store, &receipt, false),
        Err(AiError::ReorganizeStale)
    ));
    assert_eq!(
        fs::read_to_string(f.doc_path(&format!("grupo/{doc}"))).unwrap(),
        "Edição posterior"
    );
}

#[test]
fn trava_impede_analises_concorrentes_sem_gravar() {
    let f = fixture();
    let fp = reorganize::fingerprint(&f.store).unwrap();
    let lease = Lease::acquire(&f.root()).unwrap();
    assert!(matches!(
        Lease::acquire(&f.root()),
        Err(AiError::ReorganizeBusy)
    ));
    drop(lease);
    drop(Lease::acquire(&f.root()).unwrap());
    assert_eq!(reorganize::fingerprint(&f.store).unwrap(), fp);
    let schema: Value = serde_json::from_str(reorganize::SCHEMA).unwrap();
    assert!(schema["properties"].is_object());
}

#[test]
fn prompt_e_recibo_tem_o_formato_do_swift() {
    let f = fixture();
    f.topic("Regras");
    let prompt = reorganize::prompt(&f.store).unwrap();
    assert!(
        prompt.starts_with("Analise a organização deste projeto usando somente Read, Glob e Grep.")
    );
    assert!(prompt.contains("Catálogo (concept/slug e itemID para revisões):\n["));
    assert!(prompt.contains("\"concept\" : \"rules\""));
    assert!(prompt.ends_with("]\n"));
    // recibo vazio: mapas vazios no formato do Foundation
    let p = f.proposal(vec![]);
    let receipt = f.apply_all(&p);
    let text = json::to_vdjson(&serde_json::to_value(&receipt).unwrap());
    assert!(text.contains("\"after\" : {\n\n  }"), "{text}");
    assert!(text.contains("\"createdDirectories\" : [\n\n  ]"));
}
