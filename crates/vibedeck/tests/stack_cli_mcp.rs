//! Integração: `stack` / `patterns` (CLI) e as tools MCP da área, contra um Skill Icons local.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::thread;

use serde_json::{Value, json};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct Dir(PathBuf);

impl Dir {
    fn new() -> Self {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let p = std::env::temp_dir().join(format!("vibedeck-stack-it-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&p).unwrap();
        std::fs::write(p.join("vibedeck.json"), "{\"name\":\"t\"}").unwrap();
        Dir(p)
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct Mock {
    url: String,
    stop: Arc<AtomicBool>,
}

impl Drop for Mock {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = TcpStream::connect(
            self.url
                .trim_start_matches("http://")
                .trim_end_matches("/mcp"),
        );
    }
}

fn read_request(stream: &mut TcpStream) -> Option<Value> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 1024];
    let header_end = loop {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(p) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break p + 4;
        }
    };
    let head = String::from_utf8_lossy(&buf[..header_end]).to_lowercase();
    let len: usize = head
        .lines()
        .find_map(|l| l.strip_prefix("content-length:"))
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0);
    while buf.len() < header_end + len {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
    }
    serde_json::from_slice(&buf[header_end..header_end + len]).ok()
}

fn rpc_text(payload: &Value) -> String {
    json!({"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":payload.to_string()}]}})
        .to_string()
}

fn mock() -> Mock {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/mcp", listener.local_addr().unwrap());
    let stop = Arc::new(AtomicBool::new(false));
    let stop2 = stop.clone();
    thread::spawn(move || {
        for stream in listener.incoming() {
            if stop2.load(Ordering::SeqCst) {
                break;
            }
            let Ok(mut stream) = stream else { continue };
            let Some(body) = read_request(&mut stream) else {
                continue;
            };
            let payload = match body["params"]["name"].as_str() {
                Some("skill_icons_badge") => {
                    json!({"url":"https://img.test/b.svg","icons":body["params"]["arguments"]["icons"]})
                }
                _ => json!({"total": 3, "icons": [
                    {"id":"swift","name":"Swift","category":"language","themed":false,"aliases":[]},
                    {"id":"kubernetes","name":"Kubernetes","category":"devops","themed":false,"aliases":["k8s"]},
                    {"id":"rust","name":"Rust","category":"language","themed":true,"aliases":[]}
                ]}),
            };
            let text = rpc_text(&payload);
            let _ = write!(
                stream,
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}",
                text.len()
            );
        }
    });
    Mock { url, stop }
}

fn run(args: &[&str], dir: &Path, url: &str, input: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .args(args)
        .current_dir(dir)
        .env("VIBEDECK_SKILL_ICONS_URL", url)
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
    (
        out.status.code().unwrap(),
        String::from_utf8(out.stdout).unwrap(),
        String::from_utf8(out.stderr).unwrap(),
    )
}

/// Chama uma tool pelo servidor MCP; devolve (isError, texto).
fn call(dir: &Path, url: &str, name: &str, args: Value) -> (bool, String) {
    let msgs = [
        json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
        json!({"jsonrpc":"2.0","method":"notifications/initialized"}),
        json!({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":name,"arguments":args}}),
    ];
    let input: String = msgs.iter().map(|m| format!("{m}\n")).collect();
    let (code, stdout, stderr) = run(&["mcp"], dir, url, &input);
    assert_eq!(code, 0, "{stderr}");
    let reply: Value = serde_json::from_str(stdout.lines().nth(1).unwrap()).unwrap();
    let result = &reply["result"];
    (
        result["isError"] == true,
        result["content"][0]["text"].as_str().unwrap().to_string(),
    )
}

#[test]
fn cli_stack_add_list_note_move_remove_badge() {
    let (p, m) = (Dir::new(), mock());
    let (code, out, _) = run(&["stack"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    assert!(out.contains("Stack vazia"));

    let (code, out, err) = run(
        &["stack", "add", "swift", "k8s", "--note", "base"],
        &p.0,
        &m.url,
        "",
    );
    assert_eq!(code, 0, "{err}");
    assert!(out.contains("swift  Swift"), "{out}");
    assert!(out.contains("kubernetes  Kubernetes"), "{out}");
    let readme = std::fs::read_to_string(p.0.join("README.md")).unwrap();
    assert!(readme.contains("https://img.test/b.svg"), "{readme}");

    let (_, out, _) = run(&["stack", "--json"], &p.0, &m.url, "");
    let stack: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(stack[0]["icon"], "swift");
    assert_eq!(stack[1]["note"], "base");

    let (code, _, _) = run(&["stack", "note", "kube", "novo"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    let (code, out, _) = run(
        &["stack", "move", "kubernetes", "0", "--json"],
        &p.0,
        &m.url,
        "",
    );
    assert_eq!(code, 0);
    let change: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(change["stack"][0]["icon"], "kubernetes");
    assert_eq!(change["stack"][0]["note"], "novo");

    let (code, out, _) = run(&["stack", "badge"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    assert!(out.starts_with("![Stack]("), "{out}");

    let (code, _, err) = run(&["stack", "remove", "zzz"], &p.0, &m.url, "");
    assert_eq!(code, 1);
    assert!(
        err.contains("Tecnologia não encontrada na stack: zzz"),
        "{err}"
    );
    let (code, _, _) = run(
        &["stack", "remove", "swift", "kubernetes"],
        &p.0,
        &m.url,
        "",
    );
    assert_eq!(code, 0);
    let (_, out, _) = run(&["stack", "badge", "--json"], &p.0, &m.url, "");
    assert_eq!(out.trim(), "null");
}

#[test]
fn cli_stack_add_desconhecido_nao_grava() {
    let (p, m) = (Dir::new(), mock());
    let (code, _, err) = run(&["stack", "add", "swift", "zzzz"], &p.0, &m.url, "");
    assert_eq!(code, 1);
    assert!(
        err.contains("Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado"),
        "{err}"
    );
    let (_, out, _) = run(&["stack", "--json"], &p.0, &m.url, "");
    assert_eq!(serde_json::from_str::<Value>(&out).unwrap(), json!([]));
}

#[test]
fn cli_stack_search_marca_o_que_esta_na_stack() {
    let (p, m) = (Dir::new(), mock());
    run(&["stack", "add", "rust"], &p.0, &m.url, "");
    let (code, out, _) = run(&["stack", "search"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    assert!(out.contains("✓ rust  Rust  [language]"), "{out}");
    assert!(out.contains("  swift  Swift  [language]"), "{out}");
}

#[test]
fn cli_stack_sem_rede_falha_com_mensagem() {
    let p = Dir::new();
    let closed = {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        format!("http://{}/mcp", l.local_addr().unwrap())
    };
    let (code, _, err) = run(&["stack", "add", "swift"], &p.0, &closed, "");
    assert_eq!(code, 1);
    assert!(err.contains("Skill Icons indisponível"), "{err}");
}

#[test]
fn cli_patterns_ciclo_completo() {
    let (p, m) = (Dir::new(), mock());
    let (code, out, _) = run(&["patterns", "catalog", "tdd"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    assert!(out.contains("tdd"), "{out}");

    let (code, out, err) = run(
        &[
            "patterns", "add", "tdd", "--path", "src/**", "--note", "sempre",
        ],
        &p.0,
        &m.url,
        "",
    );
    assert_eq!(code, 0, "{err}");
    assert!(out.contains("tdd") && out.contains("src/**"), "{out}");
    assert!(
        std::fs::read_dir(p.0.join(".vibedeck/rules"))
            .unwrap()
            .count()
            >= 1
    );

    let (code, _, err) = run(
        &[
            "patterns",
            "add",
            "--custom",
            "Feature folders",
            "--rule",
            "Uma pasta por feature",
        ],
        &p.0,
        &m.url,
        "",
    );
    assert_eq!(code, 0, "{err}");
    let (_, out, _) = run(&["patterns", "--json"], &p.0, &m.url, "");
    let list: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(list.as_array().unwrap().len(), 2);

    let (code, _, err) = run(&["patterns", "add", "--custom", "X"], &p.0, &m.url, "");
    assert_eq!(code, 1);
    assert!(err.contains("--rule"), "{err}");
    let (code, _, err) = run(&["patterns", "add", "inexistente-zzz"], &p.0, &m.url, "");
    assert_eq!(code, 1);
    assert!(
        err.contains("Padrão(ões) desconhecido(s) no catálogo"),
        "{err}"
    );

    let (code, _, _) = run(&["patterns", "move", "tdd", "1"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    let (code, _, _) = run(&["patterns", "remove", "tdd"], &p.0, &m.url, "");
    assert_eq!(code, 0);
    let (_, out, _) = run(&["patterns", "--json"], &p.0, &m.url, "");
    let list: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(list.as_array().unwrap().len(), 1);
}

#[test]
fn mcp_stack_tools() {
    let (p, m) = (Dir::new(), mock());
    let (err, text) = call(
        &p.0,
        &m.url,
        "add_stack",
        json!({"icons":["swift","k8s"],"note":"n"}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["items"].as_array().unwrap().len(), 2);
    assert_eq!(v["stack"][1]["icon"], "kubernetes");

    let (_, text) = call(&p.0, &m.url, "list_stack", json!({}));
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["badge"], "https://img.test/b.svg");
    assert_eq!(v["stack"].as_array().unwrap().len(), 2);

    let (_, text) = call(&p.0, &m.url, "search_stack_icons", json!({"query":"s"}));
    let v: Value = serde_json::from_str(&text).unwrap();
    let swift = v
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == "swift")
        .unwrap();
    assert_eq!(swift["inStack"], true);
    let rust = v
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == "rust")
        .unwrap();
    assert_eq!(rust["inStack"], false);
    assert_eq!(rust["themed"], true);

    let (err, text) = call(&p.0, &m.url, "update_stack", json!({"icon":"swift"}));
    assert!(err);
    assert!(text.contains("Informe note ou position."), "{text}");
    let (err, text) = call(
        &p.0,
        &m.url,
        "update_stack",
        json!({"icon":"swift","position":1,"note":""}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["stack"][1]["icon"], "swift");

    let (err, text) = call(&p.0, &m.url, "add_stack", json!({"icons":[]}));
    assert!(err);
    assert!(text.contains("Parâmetro obrigatório: icons"), "{text}");
    let (err, text) = call(&p.0, &m.url, "remove_stack", json!({"icons":["nada"]}));
    assert!(err);
    assert!(
        text.contains("Tecnologia não encontrada na stack: nada"),
        "{text}"
    );
    let (err, _) = call(&p.0, &m.url, "remove_stack", json!({"icons":["swift"]}));
    assert!(!err);
}

#[test]
fn mcp_pattern_tools() {
    let (p, m) = (Dir::new(), mock());
    let (_, text) = call(&p.0, &m.url, "pattern_catalog", json!({"query":"tdd"}));
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v[0]["id"], "tdd");
    assert_eq!(v[0]["inProject"], false);
    assert!(v[0]["rules"][0].is_string());

    let (err, text) = call(
        &p.0,
        &m.url,
        "add_pattern",
        json!({"patterns":["tdd"],"paths":["src/**"]}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    let row = &v["patterns"][0];
    assert_eq!(row["id"], "tdd");
    assert_eq!(row["author"], "ai");
    assert_eq!(row["paths"], json!(["src/**"]));
    assert!(row["topic"].is_string());
    assert!(!row["rules"].as_array().unwrap().is_empty());

    let (err, text) = call(&p.0, &m.url, "add_pattern", json!({"name":"Custom"}));
    assert!(err);
    assert!(
        text.contains("Padrão personalizado precisa de rules."),
        "{text}"
    );
    let (err, text) = call(&p.0, &m.url, "add_pattern", json!({}));
    assert!(err);
    assert!(
        text.contains("Informe patterns (catálogo) ou name + rules."),
        "{text}"
    );
    let (err, text) = call(
        &p.0,
        &m.url,
        "add_pattern",
        json!({"name":"Custom","rules":["R1"],"summary":"s"}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["patterns"].as_array().unwrap().len(), 2);

    let (err, text) = call(&p.0, &m.url, "update_pattern", json!({"pattern":"tdd"}));
    assert!(err);
    assert!(text.contains("Informe note, paths ou position."), "{text}");
    let (err, text) = call(
        &p.0,
        &m.url,
        "update_pattern",
        json!({"pattern":"tdd","note":"x","paths":[],"position":1}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["patterns"][1]["id"], "tdd");
    assert_eq!(v["patterns"][1]["note"], "x");
    assert_eq!(v["patterns"][1]["paths"], json!([]));

    let (_, text) = call(&p.0, &m.url, "list_patterns", json!({}));
    assert!(text.contains("\"patterns\""));
    let (err, text) = call(&p.0, &m.url, "remove_pattern", json!({}));
    assert!(err);
    assert!(text.contains("Parâmetro obrigatório: patterns"), "{text}");
    let (err, text) = call(&p.0, &m.url, "remove_pattern", json!({"patterns":["tdd"]}));
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["patterns"].as_array().unwrap().len(), 1);
}
