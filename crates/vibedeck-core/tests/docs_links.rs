//! Docs vinculados por symlink (D4): testes com symlinks reais em projeto temporário.
#![cfg(unix)]

use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;

use vibedeck_core::Store;
use vibedeck_core::docs::{self, DocError};
use vibedeck_core::model::Author;

fn project() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "teste", None).unwrap();
    store.ensure_directories().unwrap();
    (dir, store)
}

fn is_link(p: &Path) -> bool {
    fs::symlink_metadata(p).unwrap().file_type().is_symlink()
}

#[test]
fn md_da_raiz_vira_symlink_relativo_ao_listar() {
    let (dir, store) = project();
    fs::write(dir.path().join("README.md"), "# Leia-me\n\ncorpo").unwrap();
    fs::write(dir.path().join("nota.txt"), "x").unwrap();
    let list = docs::list_docs(&store).unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].slug, "readme");
    assert_eq!(list[0].title, "Leia-me");
    let l = list[0].link.as_ref().unwrap();
    assert_eq!((l.target.as_str(), l.broken), ("README.md", false));
    let link = store.data_dir().join("docs/readme.md");
    assert!(is_link(&link));
    assert_eq!(
        fs::read_link(&link).unwrap().to_str().unwrap(),
        "../../README.md"
    );
    assert!(docs::read_doc(&store, "readme").unwrap().contains("corpo"));
}

#[test]
fn editar_grava_no_alvo_e_mantem_o_link() {
    let (dir, store) = project();
    fs::write(dir.path().join("AGENTS.md"), "# A\n").unwrap();
    docs::list_docs(&store).unwrap();
    docs::write_doc(&store, "agents", "# Novo\n\ntexto").unwrap();
    assert_eq!(
        fs::read_to_string(dir.path().join("AGENTS.md")).unwrap(),
        "# Novo\n\ntexto"
    );
    assert!(is_link(&store.data_dir().join("docs/agents.md")));
}

#[test]
fn colisao_de_slug_usa_sufixo_raiz() {
    let (dir, store) = project();
    docs::create_doc(&store, "Readme", "", Author::Human, None).unwrap();
    fs::write(dir.path().join("README.md"), "# R\n").unwrap();
    let slugs: Vec<_> = docs::list_docs(&store)
        .unwrap()
        .into_iter()
        .map(|d| d.slug)
        .collect();
    assert!(slugs.contains(&"readme".to_string()));
    assert!(slugs.contains(&"readme-raiz".to_string()));
    assert!(!is_link(&store.data_dir().join("docs/readme.md")));
    assert!(is_link(&store.data_dir().join("docs/readme-raiz.md")));
}

#[test]
fn link_quebrado_avisa_e_remove_so_o_link() {
    let (dir, store) = project();
    fs::write(dir.path().join("X.md"), "# X\n").unwrap();
    docs::list_docs(&store).unwrap();
    fs::remove_file(dir.path().join("X.md")).unwrap();
    let listing = docs::list_docs_detailed(&store).unwrap();
    assert_eq!(listing.docs.len(), 1);
    assert!(listing.docs[0].link.as_ref().unwrap().broken);
    assert_eq!(listing.warnings.len(), 1);
    assert!(listing.warnings[0].contains("quebrado"));
    assert!(matches!(
        docs::read_doc(&store, "x"),
        Err(DocError::BrokenLink { .. })
    ));
    assert!(matches!(
        docs::write_doc(&store, "x", "t"),
        Err(DocError::BrokenLink { .. })
    ));
    assert!(!dir.path().join("X.md").exists());
    docs::unlink_doc(&store, "x").unwrap();
    assert!(fs::symlink_metadata(store.data_dir().join("docs/x.md")).is_err());
}

#[test]
fn apagar_doc_vinculado_nao_toca_a_origem() {
    let (dir, store) = project();
    fs::write(dir.path().join("KEEP.md"), "# K\n").unwrap();
    docs::list_docs(&store).unwrap();
    docs::delete_doc(&store, "keep").unwrap();
    assert!(dir.path().join("KEEP.md").exists());
    assert!(fs::symlink_metadata(store.data_dir().join("docs/keep.md")).is_err());
}

#[test]
fn nunca_segue_link_para_fora_da_raiz() {
    let (dir, store) = project();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("segredo.md"), "# Segredo\n").unwrap();
    let docs_dir = store.data_dir().join("docs");
    fs::create_dir_all(&docs_dir).unwrap();
    symlink(outside.path().join("segredo.md"), docs_dir.join("evil.md")).unwrap();
    // subpasta da raiz e encadeado também são recusados
    fs::create_dir_all(dir.path().join("sub")).unwrap();
    fs::write(dir.path().join("sub/in.md"), "# in\n").unwrap();
    symlink("../../sub/in.md", docs_dir.join("sub-in.md")).unwrap();
    let listing = docs::list_docs_detailed(&store).unwrap();
    assert!(listing.docs.is_empty());
    assert_eq!(listing.warnings.len(), 2);
    assert!(docs::read_doc(&store, "evil").is_err());
    assert!(docs::write_doc(&store, "evil", "pwn").is_err());
    assert_eq!(
        fs::read_to_string(outside.path().join("segredo.md")).unwrap(),
        "# Segredo\n"
    );
}

#[test]
fn json_traz_campos_opcionais_so_para_vinculados() {
    let (dir, store) = project();
    docs::create_doc(&store, "Comum", "", Author::Human, None).unwrap();
    fs::write(dir.path().join("README.md"), "# R\n").unwrap();
    let list = docs::list_docs(&store).unwrap();
    let comum = list.iter().find(|d| d.slug == "comum").unwrap();
    let readme = list.iter().find(|d| d.slug == "readme").unwrap();
    assert!(comum.to_row_json().get("linked").is_none());
    let v = readme.to_row_json();
    assert_eq!(v["linked"], true);
    assert_eq!(v["target"], "README.md");
    assert!(v.get("broken").is_none());
}

#[test]
fn desvincular_persiste_e_link_doc_revincula() {
    let (dir, store) = project();
    fs::write(dir.path().join("README.md"), "# R\n").unwrap();
    fs::write(dir.path().join("NOTAS.md"), "# N\n").unwrap();
    docs::list_docs(&store).unwrap();
    docs::unlink_doc(&store, "readme").unwrap();
    let slugs: Vec<_> = docs::list_docs(&store)
        .unwrap()
        .into_iter()
        .map(|d| d.slug)
        .collect();
    assert_eq!(slugs, ["notas"]);
    assert!(fs::symlink_metadata(store.data_dir().join("docs/readme.md")).is_err());
    assert_eq!(
        fs::read_to_string(store.data_dir().join("docs/.unlinked")).unwrap(),
        "README.md\n"
    );
    assert!(dir.path().join("README.md").exists());
    // apagar (delete_doc) também registra
    docs::delete_doc(&store, "notas").unwrap();
    assert!(docs::list_docs(&store).unwrap().is_empty());
    // revincular
    assert_eq!(
        docs::links::link_doc(&store, "README.md").unwrap(),
        "readme"
    );
    assert!(is_link(&store.data_dir().join("docs/readme.md")));
    assert_eq!(docs::list_docs(&store).unwrap().len(), 1);
    assert_eq!(
        fs::read_to_string(store.data_dir().join("docs/.unlinked")).unwrap(),
        "NOTAS.md\n"
    );
    assert!(matches!(
        docs::links::link_doc(&store, "nada.md"),
        Err(DocError::NotRootMarkdown(_))
    ));
    assert!(matches!(
        docs::links::link_doc(&store, "../x.md"),
        Err(DocError::NotRootMarkdown(_))
    ));
}

#[test]
fn desvincular_quebrado_e_aplicar_propostas_geradas() {
    let (dir, store) = project();
    fs::write(dir.path().join("X.md"), "# X\n").unwrap();
    docs::list_docs(&store).unwrap();
    fs::remove_file(dir.path().join("X.md")).unwrap();
    docs::unlink_doc(&store, "x").unwrap();
    fs::write(dir.path().join("X.md"), "# X\n").unwrap();
    assert!(docs::list_docs(&store).unwrap().is_empty());

    use docs::generate::{Accepted, apply};
    let a = |t: &str, g: Option<&str>| Accepted {
        title: t.into(),
        content: "c".into(),
        group: g.map(str::to_string),
    };
    let slugs = apply(
        &store,
        &[a("Um", None), a("Dois", Some("g")), a("", None)],
        "",
    )
    .unwrap();
    assert_eq!(slugs, ["um", "g/dois"]);
    assert!(apply(&store, &[a("", None)], "").is_err());
    assert!(apply(&store, &[a("Ok", None), a("Mau", Some("../fora"))], "").is_err());
    assert!(docs::read_doc(&store, "ok").is_err(), "tudo ou nada");
}
