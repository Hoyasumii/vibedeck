//! Padrões: catálogo, tópicos de regras criados/atualizados/apagados e persistência em `vibedeck.json`.

use std::fs;

use vibedeck_core::Store;
use vibedeck_core::model::{Author, RuleSeverity, RuleTopic};
use vibedeck_core::stack::{PatternCatalog, StackError};

fn store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "Demo", None).unwrap();
    (dir, store)
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

fn ids(store: &Store) -> Vec<String> {
    store
        .project()
        .unwrap()
        .patterns
        .into_iter()
        .map(|p| p.id)
        .collect()
}

#[test]
fn todo_template_cria_seu_topico() {
    let (_d, store) = store();
    let all: Vec<String> = PatternCatalog::all().iter().map(|t| t.id.clone()).collect();
    let added = store.add_patterns(&all, None, None, Author::Ai).unwrap();
    assert_eq!(added.len(), PatternCatalog::all().len());
    for t in PatternCatalog::all() {
        let pattern = added.iter().find(|p| p.id == t.id).unwrap();
        let topic = store.pattern_topic(pattern).unwrap().value;
        assert_eq!(topic.source_pattern.as_deref(), Some(t.id.as_str()));
        assert_eq!(topic.rules.len(), t.rules.len());
        assert_eq!(topic.title, format!("Padrão: {}", t.name));
        assert_eq!(topic.tags, ["padrao"]);
    }
}

#[test]
fn padroes_vazios_sao_omitidos() {
    let (_d, store) = store();
    let raw = fs::read_to_string(store.root().join("vibedeck.json")).unwrap();
    assert!(!raw.contains("\"patterns\""));
    assert!(store.project().unwrap().patterns.is_empty());
}

#[test]
fn catalogo_cria_topico_global_com_regras_do_template() {
    let (_d, store) = store();
    let added = store
        .add_patterns(&s(&["tdd"]), Some("Swift Testing"), None, Author::Ai)
        .unwrap();
    assert_eq!(added[0].id, "tdd");
    let pattern = store.project().unwrap().patterns.remove(0);
    assert_eq!(pattern.author, Author::Ai);
    assert_eq!(pattern.topic.as_deref(), Some("padrao-tdd"));
    let rec = store.pattern_topic(&pattern).unwrap();
    assert_eq!(rec.slug, "padrao-tdd");
    assert!(rec.value.is_global());
    assert_eq!(
        rec.value.rules.len(),
        PatternCatalog::find("tdd").unwrap().rules.len()
    );
    assert!(
        rec.value
            .description
            .unwrap()
            .contains("No projeto: Swift Testing")
    );
    assert!(rec.value.rules.iter().all(|r| r.author == Author::Ai));
}

#[test]
fn paths_escopam_o_topico() {
    let (_d, store) = store();
    store
        .add_patterns(
            &s(&["hexagonal"]),
            None,
            Some(&s(&["Sources/Core/**", "  "])),
            Author::Human,
        )
        .unwrap();
    let pattern = store.project().unwrap().patterns.remove(0);
    let rec = store.pattern_topic(&pattern).unwrap();
    assert_eq!(rec.value.paths, ["Sources/Core/**"]);
    store.set_pattern_paths("hexagonal", &[]).unwrap();
    assert!(store.pattern_topic(&pattern).unwrap().value.is_global());
}

#[test]
fn adicionar_duas_vezes_mantem_um_topico_e_atualiza_a_nota() {
    let (_d, store) = store();
    store
        .add_patterns(&s(&["cqrs"]), None, None, Author::Human)
        .unwrap();
    store
        .add_patterns(
            &s(&["CQRS"]),
            Some("Só no módulo de pedidos"),
            None,
            Author::Human,
        )
        .unwrap();
    let patterns = store.project().unwrap().patterns;
    assert_eq!(patterns.len(), 1);
    assert_eq!(patterns[0].note.as_deref(), Some("Só no módulo de pedidos"));
    let topics = store.rule_topics().unwrap();
    assert_eq!(
        topics
            .iter()
            .filter(|t| t.value.source_pattern.as_deref() == Some("cqrs"))
            .count(),
        1
    );
    assert_eq!(topics.len(), 1);
}

#[test]
fn desconhecido_recusa_tudo_com_sugestoes() {
    let (_d, store) = store();
    assert!(
        store
            .add_patterns(&s(&["tdd", "hexagon"]), None, None, Author::Human)
            .is_err()
    );
    assert!(store.project().unwrap().patterns.is_empty());
    assert!(store.rule_topics().unwrap().is_empty());
    match store
        .add_patterns(&s(&["hexagon"]), None, None, Author::Human)
        .unwrap_err()
    {
        StackError::UnknownPatterns(m) => assert!(m["hexagon"].contains(&"hexagonal".to_string())),
        e => panic!("{e}"),
    }
}

#[test]
fn personalizado_ganha_uma_regra_must_por_linha() {
    let (_d, store) = store();
    let pattern = store
        .add_custom_pattern(
            "Feature folders",
            Some("Código agrupado por funcionalidade"),
            &s(&["Uma pasta por feature", " ", "Sem pasta utils"]),
            None,
            None,
            Author::Human,
        )
        .unwrap();
    assert_eq!(pattern.id, "feature-folders");
    assert_eq!(pattern.category.as_deref(), Some("custom"));
    let topic: RuleTopic = store.pattern_topic(&pattern).unwrap().value;
    let texts: Vec<_> = topic.rules.iter().map(|r| r.text.as_str()).collect();
    assert_eq!(texts, ["Uma pasta por feature", "Sem pasta utils"]);
    assert!(topic.rules.iter().all(|r| r.severity == RuleSeverity::Must));
    // nome igual a um id do catálogo ganha id próprio
    let tdd = store
        .add_custom_pattern("TDD", None, &s(&["x"]), None, None, Author::Human)
        .unwrap();
    assert_eq!(tdd.id, "tdd-2");
    let again = store
        .add_custom_pattern("TDD", None, &s(&["x"]), None, None, Author::Human)
        .unwrap();
    assert_eq!(again.id, "tdd-3");
    assert!(
        store
            .add_custom_pattern("  ", None, &s(&["x"]), None, None, Author::Human)
            .is_err()
    );
}

#[test]
fn remover_apaga_o_topico() {
    let (_d, store) = store();
    store
        .add_patterns(&s(&["ddd", "repository"]), None, None, Author::Human)
        .unwrap();
    let removed = store.remove_patterns(&s(&["ddd"])).unwrap();
    assert_eq!(removed[0].id, "ddd");
    assert_eq!(ids(&store), ["repository"]);
    let sources: Vec<_> = store
        .rule_topics()
        .unwrap()
        .into_iter()
        .filter_map(|t| t.value.source_pattern)
        .collect();
    assert_eq!(sources, ["repository"]);
    let err = store
        .remove_patterns(&s(&["repository", "nope"]))
        .unwrap_err();
    assert_eq!(err.to_string(), "Padrão não encontrado no projeto: nope");
    assert_eq!(ids(&store), ["repository"]);
}

#[test]
fn apagar_o_topico_derruba_o_padrao() {
    let (_d, store) = store();
    store
        .add_patterns(&s(&["solid", "mvvm"]), None, None, Author::Human)
        .unwrap();
    let slug = store
        .pattern_topic(&store.project().unwrap().patterns[0])
        .unwrap()
        .slug;
    store.delete_rule_topic(&slug).unwrap();
    assert_eq!(store.release_orphaned_patterns().unwrap(), ["solid"]);
    assert_eq!(ids(&store), ["mvvm"]);
    assert!(store.release_orphaned_patterns().unwrap().is_empty());
}

#[test]
fn nota_renova_descricao_e_move_reordena() {
    let (_d, store) = store();
    store
        .add_patterns(&s(&["tdd", "solid"]), None, None, Author::Human)
        .unwrap();
    store
        .set_pattern_note("solid", Some("Protocolos no Core"))
        .unwrap();
    let solid = store.project().unwrap().patterns[1].clone();
    let description = store
        .pattern_topic(&solid)
        .unwrap()
        .value
        .description
        .unwrap();
    assert!(description.contains("No projeto: Protocolos no Core"));
    assert!(description.starts_with(&solid.summary.clone().unwrap()));
    store.set_pattern_note("solid", None).unwrap();
    assert_eq!(store.project().unwrap().patterns[1].note, None);
    let solid = store.project().unwrap().patterns[1].clone();
    assert_eq!(
        store
            .pattern_topic(&solid)
            .unwrap()
            .value
            .description
            .unwrap(),
        solid.summary.clone().unwrap()
    );
    store.move_pattern("solid", 0).unwrap();
    assert_eq!(ids(&store), ["solid", "tdd"]);
    store.move_pattern("solid", 50).unwrap();
    assert_eq!(ids(&store), ["tdd", "solid"]);
}

#[test]
fn tags_ida_e_volta_e_omitidas_quando_vazias() {
    let (_d, store) = store();
    store
        .add_patterns(&s(&["tdd"]), None, None, Author::Human)
        .unwrap();
    let raw = fs::read_to_string(store.root().join("vibedeck.json")).unwrap();
    assert!(!raw.contains("\"tags\""));
    store
        .set_pattern_tags("tdd", &s(&["qualidade", "testes"]))
        .unwrap();
    assert_eq!(
        store.project().unwrap().patterns[0].tags,
        ["qualidade", "testes"]
    );
    store.set_pattern_tags("tdd", &[]).unwrap();
    assert!(store.project().unwrap().patterns[0].tags.is_empty());
}

#[test]
fn indice_por_id_nome_catalogo_e_prefixo() {
    let (_d, store) = store();
    store
        .add_patterns(
            &s(&["hexagonal", "clean-code", "clean-architecture"]),
            None,
            None,
            Author::Human,
        )
        .unwrap();
    let p = store.project().unwrap().patterns;
    assert_eq!(store.pattern_index("hexagonal", &p).unwrap(), 0);
    assert_eq!(store.pattern_index("ARQUITETURA HEXAGONAL", &p).unwrap(), 0);
    assert_eq!(store.pattern_index("ports and adapters", &p).unwrap(), 0);
    assert_eq!(store.pattern_index("hex", &p).unwrap(), 0);
    assert_eq!(store.pattern_index("clean", &p).unwrap(), 1); // alias exato do clean-code
    assert!(store.pattern_index("clea", &p).is_err()); // prefixo ambíguo
    assert!(store.pattern_index("", &p).is_err());
    // padrão sem tópico: paths falha como TopicNotFound
    let slug = store.pattern_topic(&p[0]).unwrap().slug;
    store.delete_rule_topic(&slug).unwrap();
    let err = store.set_pattern_paths("hexagonal", &[]).unwrap_err();
    assert_eq!(
        err.to_string(),
        format!("Tópico de regras não encontrado: {slug}")
    );
}
