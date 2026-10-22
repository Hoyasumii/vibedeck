//! Integração do servidor MCP (stdio) para as tools da área Projeto.

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

struct Dir(PathBuf);

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn project(name: &str) -> Dir {
    let p = std::env::temp_dir().join(format!("vd-project-mcp-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .args(["init", "--name", "Demo"])
        .current_dir(&p)
        .output()
        .unwrap();
    assert!(out.status.success());
    Dir(p)
}

/// Roda `tools/call` para cada (nome, args) numa sessão e devolve (isError, texto) de cada uma.
fn calls(dir: &Path, calls: &[(&str, Value)]) -> Vec<(bool, String)> {
    let mut input = String::from(
        "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"1\"}}}\n",
    );
    for (i, (name, args)) in calls.iter().enumerate() {
        let m = json!({"jsonrpc":"2.0","id":i + 1,"method":"tools/call",
                       "params":{"name":name,"arguments":args}});
        input.push_str(&format!("{m}\n"));
    }
    let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .arg("mcp")
        .current_dir(dir)
        .env("VIBEDECK_LOG_DIR", dir.join("logs-out"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    String::from_utf8(out.stdout)
        .unwrap()
        .lines()
        .skip(1)
        .map(|l| {
            let v: Value = serde_json::from_str(l).unwrap();
            (
                v["result"]["isError"].as_bool().unwrap(),
                v["result"]["content"][0]["text"]
                    .as_str()
                    .unwrap()
                    .to_string(),
            )
        })
        .collect()
}

#[test]
fn get_project_links_e_tags() {
    let d = project("a");
    let r = calls(
        &d.0,
        &[
            ("add_link", json!({"url":"https://a.test","tags":"x, y"})),
            ("get_project", json!({})),
            (
                "set_tags",
                json!({"kind":"stack","ref":"nada","tags":["a"]}),
            ),
            ("set_tags", json!({"kind":"folha","ref":"x","tags":[]})),
            ("set_tags", json!({"kind":"idea","tags":[]})),
            ("add_link", json!({})),
        ],
    );
    assert!(!r[0].0);
    let link: Value = serde_json::from_str(&r[0].1).unwrap();
    assert_eq!(link["title"], "https://a.test");
    assert_eq!(link["tags"], json!(["x", "y"]));
    let p: Value = serde_json::from_str(&r[1].1).unwrap();
    assert_eq!(p["project"]["links"].as_array().unwrap().len(), 1);
    assert_eq!(p["docs"], json!([]));
    assert!(r[1].1.contains("\"groups\" : ["), "{}", r[1].1);
    assert_eq!(
        r[2],
        (true, "Tecnologia não encontrada na stack: nada".into())
    );
    assert_eq!(r[3], (true, "Invalid params: Tipo inválido: folha".into()));
    assert_eq!(
        r[4],
        (true, "Invalid params: Parâmetro obrigatório: ref".into())
    );
    assert_eq!(
        r[5],
        (true, "Invalid params: Parâmetro obrigatório: url".into())
    );
}

#[test]
fn claude_items_e_set_tags_texto() {
    let d = project("b");
    let url = "https://claude.ai/public/artifacts/abc";
    let r = calls(
        &d.0,
        &[
            (
                "add_claude_item",
                json!({"url":url,"kind":"doc","tags":["t"]}),
            ),
            ("add_claude_item", json!({"url":url,"kind":"x"})),
            (
                "add_claude_item",
                json!({"url":"https://x.test","kind":"doc"}),
            ),
            ("list_claude_items", json!({"kind":"artifact"})),
            ("list_claude_items", json!({"kind":"doc"})),
            ("list_claude_items", json!({"kind":"x"})),
        ],
    );
    let item: Value = serde_json::from_str(&r[0].1).unwrap();
    assert_eq!(item["kind"], "doc");
    assert_eq!(item["title"], "abc");
    assert_eq!(
        r[1],
        (
            true,
            "Invalid params: Tipo inválido: use artifact ou doc.".into()
        )
    );
    assert_eq!(
        r[2],
        (true, "Informe uma URL http ou https do claude.ai.".into())
    );
    assert_eq!(r[3].1.split_whitespace().collect::<String>(), "[]");
    assert_eq!(
        serde_json::from_str::<Value>(&r[4].1)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert!(r[5].0);
}

#[test]
fn export_graph_e_read_logs() {
    let d = project("c");
    let r = calls(&d.0, &[("export_graph", json!({}))]);
    assert!(r[0].0 && r[0].1.starts_with("Grafo: "), "{:?}", r[0]);
    std::fs::create_dir_all(d.0.join("graphify-out")).unwrap();
    std::fs::write(
        d.0.join("graphify-out/graph.json"),
        r#"{"nodes":[{"id":"a","label":"A"}],"links":[]}"#,
    )
    .unwrap();
    let r = calls(
        &d.0,
        &[
            ("export_graph", json!({})),
            ("read_logs", json!({})),
            ("read_logs", json!({"since":"xx"})),
            (
                "read_logs",
                json!({"level":"info","components":"cli, mcp","limit":0}),
            ),
        ],
    );
    assert_eq!(
        r[0],
        (
            false,
            "Visualização offline exportada em graphify-out/graph.html".into()
        )
    );
    assert!(d.0.join("graphify-out/graph.html").is_file());
    // O MCP grava sucesso/falha das ferramentas e as gravações do projeto (sem nunca citar argumentos).
    let logs: serde_json::Value = serde_json::from_str(&r[1].1).unwrap();
    let events: Vec<&str> = logs
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["event"].as_str().unwrap())
        .collect();
    for wanted in ["mcp.tool_called", "mcp.tool_failed", "store.file_written"] {
        assert!(events.contains(&wanted), "{wanted} ausente em {events:?}");
    }
    let written = logs
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["event"] == "store.file_written")
        .unwrap();
    assert_eq!(written["context"]["file"], "graphify-out/graph.html");
    assert_eq!(written["context"]["undo"], "Salvar");
    assert_eq!(
        r[2],
        (
            true,
            "Filtro de log inválido: xx. Use, por exemplo, 30m, 24h ou 7d.".into()
        )
    );
    assert!(!r[3].0);
}
