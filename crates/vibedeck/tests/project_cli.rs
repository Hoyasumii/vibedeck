//! Integração do binário: init, status, links, claude, tag, graph, logs.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

struct Dir(PathBuf);

impl Dir {
    fn new(name: &str) -> Dir {
        let p = std::env::temp_dir().join(format!("vd-project-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        Dir(p)
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn vd(dir: &Path, args: &[&str]) -> (i32, String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .args(args)
        .current_dir(dir)
        .env("VIBEDECK_LOG_DIR", dir.join("logs-out"))
        .stdin(Stdio::null())
        .output()
        .unwrap();
    (
        out.status.code().unwrap(),
        String::from_utf8(out.stdout).unwrap(),
        String::from_utf8(out.stderr).unwrap(),
    )
}

fn project(name: &str) -> Dir {
    let d = Dir::new(name);
    let (code, out, _) = vd(&d.0, &["init", "--name", "Demo", "--description", "Desc"]);
    assert_eq!(code, 0);
    assert!(out.starts_with("Projeto criado em "), "{out}");
    d
}

#[test]
fn init_cria_projeto_e_recusa_repetir() {
    let d = project("init");
    assert!(d.0.join("vibedeck.json").is_file());
    for sub in ["docs", "reviews", "rules", "ideas", "agents", "skills"] {
        assert!(d.0.join(".vibedeck").join(sub).is_dir(), "{sub}");
    }
    // O guia nasce junto com o projeto.
    for guide in ["AGENTS.md", "guide.md"] {
        assert!(d.0.join(".vibedeck").join(guide).is_file(), "{guide}");
    }
    let (code, _, err) = vd(&d.0, &["init"]);
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: "), "{err}");
}

#[test]
fn status_texto_e_json() {
    let d = project("status");
    let (code, out, _) = vd(&d.0, &["status"]);
    assert_eq!(code, 0);
    let lines: Vec<&str> = out.lines().collect();
    assert!(lines[0].starts_with("Demo — "), "{out}");
    assert_eq!(lines[1], "Desc");
    assert!(
        out.contains("\nLinks: 0  Docs: 0  Grupos de revisão: 0\n"),
        "{out}"
    );
    assert!(out.ends_with("Tópicos de regras: 0 (0 regra(s))  Ideias: 0 (0 abertas)  Agentes: 0  Comandos: 0  Skills: 0  Workflows: 0\n"));
    let (_, json, _) = vd(&d.0, &["status", "--json"]);
    let v: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(v["project"]["name"], "Demo");
    assert_eq!(v["ruleTopics"], serde_json::json!([]));
    assert!(json.contains("\"docs\" : ["), "{json}");
}

#[test]
fn links_add_list_remove() {
    let d = project("links");
    let (code, id, _) = vd(
        &d.0,
        &[
            "links",
            "add",
            "https://a.test",
            "--title",
            "A",
            "--tags",
            "x",
            "y",
        ],
    );
    assert_eq!(code, 0);
    let id = id.trim().to_string();
    assert_eq!(id.len(), 36);
    let (_, out, _) = vd(&d.0, &["links"]);
    assert_eq!(out, format!("{}  A  https://a.test  #x #y\n", &id[..8]));
    let (_, json, _) = vd(&d.0, &["links", "list", "--json"]);
    assert!(json.contains("\"title\" : \"A\""), "{json}");
    let (code, _, err) = vd(&d.0, &["links", "remove", "zzzz"]);
    assert_eq!(
        (code, err.as_str()),
        (1, "Error: Link não encontrado: zzzz\n")
    );
    let (code, _, _) = vd(&d.0, &["links", "remove", &id[..8].to_lowercase()]);
    assert_eq!(code, 0);
    assert_eq!(vd(&d.0, &["links"]).1, "");
}

#[test]
fn claude_items() {
    let d = project("claude");
    let url = "https://claude.ai/public/artifacts/abc";
    let (code, id, _) = vd(
        &d.0,
        &["claude", "add", url, "--kind", "artifact", "--tags", "t"],
    );
    assert_eq!(code, 0);
    let (_, json, _) = vd(
        &d.0,
        &[
            "claude", "add", url, "--kind", "doc", "--title", "Meu", "--json",
        ],
    );
    assert!(
        json.contains("\"kind\" : \"doc\"") && json.contains("\"title\" : \"Meu\""),
        "{json}"
    );
    let (_, out, _) = vd(&d.0, &["claude", "list", "--kind", "artifact"]);
    assert!(
        out.starts_with(&format!("{}  [Artefato] abc  {url}  ", &id.trim()[..8])),
        "{out}"
    );
    assert!(out.ends_with("  #t\n"), "{out}");
    let (_, all, _) = vd(&d.0, &["claude"]);
    assert_eq!(all.lines().count(), 2);
    let (code, _, err) = vd(
        &d.0,
        &["claude", "add", "https://evil.test/x", "--kind", "doc"],
    );
    assert_eq!(
        (code, err.as_str()),
        (1, "Error: Informe uma URL http ou https do claude.ai.\n")
    );
    assert_eq!(vd(&d.0, &["claude", "add", url]).0, 64);
    let (code, _, _) = vd(&d.0, &["claude", "remove", "Meu"]);
    assert_eq!(code, 0);
    assert_eq!(vd(&d.0, &["claude"]).1.lines().count(), 1);
    let (code, _, err) = vd(&d.0, &["claude", "remove", "nada"]);
    assert_eq!(
        (code, err.as_str()),
        (1, "Error: Item do Claude não encontrado: nada\n")
    );
}

#[test]
fn tag_stack_pattern_e_erros() {
    let d = project("tag");
    let mut manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(d.0.join("vibedeck.json")).unwrap()).unwrap();
    manifest["stack"] = serde_json::json!([{"name": "Rust", "icon": "rust"}]);
    std::fs::write(d.0.join("vibedeck.json"), manifest.to_string()).unwrap();
    let (code, out, _) = vd(&d.0, &["tag", "stack", "rust", "a", "b"]);
    assert_eq!((code, out.as_str()), (0, "Tags: a, b\n"));
    let m = std::fs::read_to_string(d.0.join("vibedeck.json")).unwrap();
    assert!(m.contains("\"a\""), "{m}");
    let (_, out, _) = vd(&d.0, &["tag", "stack", "rust"]);
    assert_eq!(out, "Tags removidas.\n");
    let (code, _, err) = vd(&d.0, &["tag", "stack", "nada", "a"]);
    assert_eq!(code, 1);
    assert!(
        err.contains("Tecnologia não encontrada na stack: nada"),
        "{err}"
    );
    assert_eq!(vd(&d.0, &["tag", "folha", "x"]).0, 64);
}

#[test]
fn graph_export() {
    let d = project("graph");
    let (code, _, err) = vd(&d.0, &["graph", "export"]);
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: Grafo: "), "{err}");
    std::fs::create_dir_all(d.0.join("graphify-out")).unwrap();
    std::fs::write(
        d.0.join("graphify-out/graph.json"),
        r#"{"nodes":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"links":[{"source":"a","target":"b"}]}"#,
    )
    .unwrap();
    let (code, out, err) = vd(&d.0, &["graph", "export"]);
    assert_eq!(code, 0, "{err}");
    assert_eq!(
        out,
        "Visualização offline exportada em graphify-out/graph.html\n"
    );
    let html = std::fs::read_to_string(d.0.join("graphify-out/graph.html")).unwrap();
    assert!(html.contains("<html") || html.contains("<!DOCTYPE") || html.contains("<!doctype"));
}

#[test]
fn logs_path_list_crashes_e_filtro_invalido() {
    let d = project("logs");
    let (code, out, _) = vd(&d.0, &["logs", "path"]);
    assert_eq!(code, 0);
    assert_eq!(out.trim(), d.0.join("logs-out").to_string_lossy());
    assert_eq!(vd(&d.0, &["logs"]).1, "Nenhuma entrada no período.\n");
    assert_eq!(
        vd(&d.0, &["logs", "crashes"]).1,
        "Nenhum crash registrado no período.\n"
    );
    let (_, json, _) = vd(&d.0, &["logs", "list", "--json"]);
    assert_eq!(json.split_whitespace().collect::<String>(), "[]");
    let (code, _, err) = vd(&d.0, &["logs", "--since", "xx"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "Error: Filtro de log inválido: xx. Use, por exemplo, 30m, 24h ou 7d.\n"
    );
    assert_eq!(vd(&d.0, &["logs", "--level", "fatal"]).0, 64);
    let (code, out, _) = vd(&d.0, &["logs", "report"]);
    assert_eq!(code, 0);
    assert!(
        out.starts_with("Relatório de diagnóstico do VibeDeck "),
        "{out}"
    );
}
