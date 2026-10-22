//! Stack: serviço com Skill Icons falso (sem rede), README e persistência em `vibedeck.json`.

use std::fs;

use vibedeck_core::Store;
use vibedeck_core::model::Author;
use vibedeck_core::stack::{
    ReadmeStack, SkillBadge, SkillIcon, SkillIconTheme, SkillIconsApi, StackError, StackService,
};

type R<T> = vibedeck_core::stack::Result<T>;

fn fixture() -> Vec<SkillIcon> {
    let mk = |id: &str, name: &str, cat: &str, themed: bool, aliases: &[&str]| SkillIcon {
        id: id.into(),
        name: name.into(),
        category: Some(cat.into()),
        themed,
        aliases: aliases.iter().map(|s| s.to_string()).collect(),
    };
    vec![
        mk("swift", "Swift", "language", false, &[]),
        mk("kubernetes", "Kubernetes", "devops", false, &["k8s"]),
        mk("nextjs", "Next.js", "frontend", true, &["next"]),
        mk("postgresql", "PostgreSQL", "database", false, &["postgres"]),
    ]
}

/// Substituto offline do servidor do Skill Icons.
struct Fake {
    failing: bool,
}

impl SkillIconsApi for Fake {
    fn search(&self, query: Option<&str>, _c: Option<&str>, _l: Option<i64>) -> R<Vec<SkillIcon>> {
        if self.failing {
            return Err(StackError::SkillIconsUnavailable("offline".into()));
        }
        Ok(fixture()
            .into_iter()
            .filter(|i| i.matches_containing(query.unwrap_or("")))
            .collect())
    }

    fn badge(
        &self,
        icons: &[String],
        _t: Option<SkillIconTheme>,
        _p: Option<i64>,
    ) -> R<SkillBadge> {
        if self.failing {
            return Err(StackError::SkillIconsUnavailable("offline".into()));
        }
        let url = format!("https://icons.test/icons?i={}", icons.join(","));
        Ok(serde_json::from_value(serde_json::json!({
            "url": url, "markdown": format!("![Stack]({url})"), "html": "", "icons": []
        }))
        .unwrap())
    }
}

fn store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::init(dir.path(), "Demo", None).unwrap();
    (dir, store)
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

fn icons(store: &Store) -> Vec<String> {
    store
        .project()
        .unwrap()
        .stack
        .into_iter()
        .map(|i| i.icon)
        .collect()
}

#[test]
fn stack_vazia_e_omitida_e_item_escrito_a_mao_decodifica() {
    let (_d, store) = store();
    let raw = fs::read_to_string(store.root().join("vibedeck.json")).unwrap();
    assert!(!raw.contains("\"stack\""));
    let hand = raw.replace(
        "\"name\" : \"Demo\"",
        "\"name\" : \"Demo\", \"stack\": [{\"icon\": \"swift\"}]",
    );
    fs::write(store.root().join("vibedeck.json"), hand).unwrap();
    let item = store.project().unwrap().stack.remove(0);
    assert_eq!((item.icon.as_str(), item.name.as_str()), ("swift", "swift"));
    // regravar normaliza: icon, name e author
    let p = store.project().unwrap();
    store.save_project(&p).unwrap();
    let v: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(store.root().join("vibedeck.json")).unwrap())
            .unwrap();
    let keys: Vec<_> = v["stack"][0].as_object().unwrap().keys().cloned().collect();
    let mut keys = keys;
    keys.sort();
    assert_eq!(keys, ["author", "icon", "name"]);
}

#[test]
fn add_remove_note_e_move() {
    let (_d, store) = store();
    let api = Fake { failing: false };
    let service = StackService::new(&store, &api);

    let added = service
        .add(&s(&["swift", "k8s"]), Some("base"), Author::Ai)
        .unwrap();
    assert_eq!(
        added
            .stack
            .iter()
            .map(|i| i.icon.as_str())
            .collect::<Vec<_>>(),
        ["swift", "kubernetes"]
    );
    assert!(
        added
            .stack
            .iter()
            .all(|i| i.author == Author::Ai && i.note.as_deref() == Some("base"))
    );
    assert!(added.readme_warning.is_none());

    // de novo: mantém o lugar; a nota nova substitui a antiga; o autor original fica
    service
        .add(&s(&["postgres", "swift"]), Some("Swift 6"), Author::Human)
        .unwrap();
    let stack = store.project().unwrap().stack;
    assert_eq!(icons(&store), ["swift", "kubernetes", "postgresql"]);
    assert_eq!(stack[0].note.as_deref(), Some("Swift 6"));
    assert_eq!(stack[0].author, Author::Ai);

    service.move_to("postgresql", 0).unwrap();
    service.set_note("Kubernetes", Some("")).unwrap();
    let stack = store.project().unwrap().stack;
    assert_eq!(icons(&store), ["postgresql", "swift", "kubernetes"]);
    assert_eq!(stack[2].note, None);

    // desconhecido não remove nada; alias passa pelo catálogo
    let err = service.remove(&s(&["k8s", "nope"])).unwrap_err();
    assert_eq!(err.to_string(), "Tecnologia não encontrada na stack: nope");
    assert_eq!(store.project().unwrap().stack.len(), 3);
    let removed = service.remove(&s(&["k8s", "postg"])).unwrap();
    assert_eq!(
        removed
            .items
            .iter()
            .map(|i| i.icon.as_str())
            .collect::<Vec<_>>(),
        ["postgresql", "kubernetes"]
    );
    assert_eq!(
        removed
            .stack
            .iter()
            .map(|i| i.icon.as_str())
            .collect::<Vec<_>>(),
        ["swift"]
    );
}

#[test]
fn icone_desconhecido_recusa_tudo_com_sugestoes() {
    let (_d, store) = store();
    let api = Fake { failing: false };
    let service = StackService::new(&store, &api);
    let err = service
        .add(&s(&["swift", "post"]), None, Author::Human)
        .unwrap_err();
    assert_eq!(
        err.to_string(),
        "Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado:\n- post (sugestões: postgresql)"
    );
    assert!(store.project().unwrap().stack.is_empty());
}

#[test]
fn badge_do_readme_acompanha_a_stack() {
    let (_d, store) = store();
    fs::write(store.readme_path(), "# Demo\n\nTexto.\n").unwrap();
    let api = Fake { failing: false };
    let service = StackService::new(&store, &api);

    service.add(&s(&["swift"]), None, Author::Human).unwrap();
    let readme = fs::read_to_string(store.readme_path()).unwrap();
    assert_eq!(
        readme,
        format!(
            "# Demo\n\n{}\n![Stack](https://icons.test/icons?i=swift)\n{}\n\nTexto.\n",
            ReadmeStack::START,
            ReadmeStack::END
        )
    );
    service.add(&s(&["k8s"]), None, Author::Human).unwrap();
    let readme = fs::read_to_string(store.readme_path()).unwrap();
    assert!(readme.contains("i=swift,kubernetes"));
    assert_eq!(readme.matches(ReadmeStack::START).count(), 1);

    service.remove(&s(&["swift", "kubernetes"])).unwrap();
    assert_eq!(
        fs::read_to_string(store.readme_path()).unwrap(),
        "# Demo\n\nTexto.\n"
    );
}

#[test]
fn offline_ainda_salva_com_aviso() {
    let (_d, store) = store();
    let fixture = fixture();
    store
        .add_stack_items(&fixture[..1], None, Author::Human)
        .unwrap();
    let api = Fake { failing: true };
    let change = StackService::new(&store, &api)
        .set_note("swift", Some("x"))
        .unwrap();
    assert_eq!(change.stack[0].note.as_deref(), Some("x"));
    let warning = change.readme_warning.unwrap();
    assert!(
        warning.contains("README.md não foi atualizado"),
        "{warning}"
    );
    assert!(warning.contains("Skill Icons indisponível: offline"));
}

#[test]
fn tags_ida_e_volta_e_omitidas_quando_vazias() {
    let (_d, store) = store();
    let fixture = fixture();
    store
        .add_stack_items(&fixture[..1], None, Author::Human)
        .unwrap();
    let raw = fs::read_to_string(store.root().join("vibedeck.json")).unwrap();
    assert!(!raw.contains("\"tags\""));
    store.set_stack_tags("swift", &s(&["app", "cli"])).unwrap();
    assert_eq!(store.project().unwrap().stack[0].tags, ["app", "cli"]);
    store.set_stack_tags("swift", &[]).unwrap();
    assert!(store.project().unwrap().stack[0].tags.is_empty());
}

#[test]
fn indice_por_id_nome_e_prefixo_unico() {
    let (_d, store) = store();
    let fx = fixture();
    store.add_stack_items(&fx, None, Author::Human).unwrap();
    let stack = store.project().unwrap().stack;
    assert_eq!(store.stack_index("nextjs", &stack).unwrap(), 2);
    assert_eq!(store.stack_index("next.JS", &stack).unwrap(), 2);
    assert_eq!(store.stack_index("kube", &stack).unwrap(), 1);
    assert!(store.stack_index("n", &stack).is_ok()); // só nextjs começa com n
    assert!(store.stack_index("p", &stack).is_ok());
    assert!(store.stack_index("", &stack).is_err());
    assert!(store.stack_index("zzz", &stack).is_err());
    // posição fora do intervalo é limitada
    store.move_stack_item("swift", 99).unwrap();
    assert_eq!(icons(&store).last().unwrap(), "swift");
    store.move_stack_item("swift", -5).unwrap();
    assert_eq!(icons(&store)[0], "swift");
}
