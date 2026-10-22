//! `Slug.make(título)` contra os nomes de arquivo reais de `.vibedeck/**` e dos anexos.

use std::path::Path;

use vibedeck_core::Store;
use vibedeck_core::slug;

fn store() -> Store {
    Store::open(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap()
}

fn leaf(s: &str) -> &str {
    s.rsplit('/').next().unwrap()
}

/// Um slug real é `make(título)` ou `make(título)-N` (colisão de `uniqueSlug`).
fn matches_title(slug_leaf: &str, title: &str) -> bool {
    let base = slug::make(title);
    if slug_leaf == base {
        return true;
    }
    slug_leaf
        .strip_prefix(&format!("{base}-"))
        .is_some_and(|n| n.parse::<u32>().is_ok())
}

/// Ideias cujo título foi editado depois da criação (o slug nasce com o título e não muda).
const RENAMED_IDEAS: &[&str] = &[
    "adicionar-agentes",
    "botao-de-descubra-em-onde-e-regras",
    "criacao-do-core/reescrita-do-vibedeck",
    "botao-de-reorganizar-regras-no-vibedeck",
    "permitir-o-agrupamento-de-ideias-revisoes-regras-docs",
    "criacao-do-core/melhorar-a-performance-do-app-apos-a-reescrita",
    "botao-de-executar-ideia-com-workflow",
    "criacao-do-core/trocar-a-linguagem-de-scripts-para-rust-e-talvez-criar-um-fr",
    "criacao-do-core/definir-arquitetura-e-padroes-do-core-rust-multiplataforma",
    "criacao-do-core/validar-mcp-rust-stdio-em-maquina-limpa-e-nuvem",
];

fn report(kind: &str, pairs: Vec<(String, String)>) {
    let bad: Vec<_> = pairs
        .iter()
        .filter(|(s, t)| !matches_title(leaf(s), t))
        .filter(|(s, _)| !(kind == "ideas" && RENAMED_IDEAS.contains(&s.as_str())))
        .collect();
    eprintln!(
        "{kind}: {} registros, {} divergentes",
        pairs.len(),
        bad.len()
    );
    for (s, t) in &bad {
        eprintln!("  {s} <- {t:?} (make = {})", slug::make(t));
    }
    assert!(bad.is_empty(), "{kind}: slugs divergentes: {bad:?}");
}

#[test]
fn record_slugs_match_titles() {
    let s = store();
    report(
        "agents",
        s.agents()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "commands",
        s.commands()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "workflows",
        s.workflows()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "skills",
        s.skills()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "reviews",
        s.review_groups()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "rules",
        s.rule_topics()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
    report(
        "ideas",
        s.ideas()
            .unwrap()
            .into_iter()
            .map(|r| (r.slug, r.value.title))
            .collect(),
    );
}

#[test]
fn attachment_names_match() {
    // Anexo = Slug(owner) + "-" + Slug(nome sem extensão) + "." + Slug(extensão).
    let owner = slug::make("Painel lateral melhorado");
    let a = format!(
        "{owner}-{}.{}",
        slug::make("Captura de Tela 2026-10-09 às 13.06.47"),
        slug::make("PNG")
    );
    let b = format!(
        "{owner}-{}.{}",
        slug::make("Captura de Tela 2026-10-09 às 13.08.52"),
        slug::make("png")
    );
    let dir = store().data_dir().join("attachments");
    assert!(dir.join(&a).is_file(), "{a}");
    assert!(dir.join(&b).is_file(), "{b}");
}
