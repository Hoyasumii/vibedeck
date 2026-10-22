//! Casos de uso da área Projeto: init, status, links, tags.

use vibedeck_core::project::{self, ProjectError, links, status, tags};

fn temp(name: &str) -> tempfile::TempDir {
    tempfile::Builder::new().prefix(name).tempdir().unwrap()
}

#[test]
fn init_usa_nome_da_pasta_e_recusa_duplicar() {
    let t = temp("proj-init");
    let store = project::init(t.path(), Some("  "), None).unwrap();
    let name = store.project().unwrap().name;
    assert_eq!(
        name,
        t.path().file_name().unwrap().to_string_lossy().as_ref()
    );
    assert!(project::init(t.path(), None, None).is_err());
}

#[test]
fn links_prefixo_case_insensitive_e_nada_gravado_sem_match() {
    let t = temp("proj-links");
    let store = project::init(t.path(), Some("P"), None).unwrap();
    let a = links::add(&store, "https://a", None, vec![]).unwrap();
    assert_eq!(a.title, "https://a");
    let before = std::fs::read(t.path().join("vibedeck.json")).unwrap();
    assert!(matches!(
        links::remove(&store, "zzzz"),
        Err(ProjectError::LinkNotFound(_))
    ));
    assert_eq!(
        std::fs::read(t.path().join("vibedeck.json")).unwrap(),
        before
    );
    let prefix = a.id.to_string()[..6].to_lowercase();
    assert_eq!(links::remove(&store, &prefix).unwrap(), 1);
    assert_eq!(links::hashtags(&["a".into(), "b".into()]), "  #a #b");
}

#[test]
fn status_conta_e_tags_mensagem() {
    let t = temp("proj-status");
    let store = project::init(t.path(), Some("P"), None).unwrap();
    let st = status::status(&store).unwrap();
    assert_eq!(st.summary.groups.len(), 0);
    assert_eq!(
        st.text_lines()[0],
        format!("P — {}", store.root().display())
    );
    assert_eq!(status::overview(&store).unwrap().docs.len(), 0);
    assert_eq!(tags::message(&[]), "Tags removidas.");
    assert_eq!(tags::message(&["a".into(), "b".into()]), "Tags: a, b");
    assert_eq!(tags::TagKind::from_mcp("rules"), None);
    assert_eq!(
        tags::TagKind::from_mcp("rule_topic"),
        Some(tags::TagKind::RuleTopic)
    );
    assert_eq!(tags::TagKind::from_cli("review_group"), None);
}
