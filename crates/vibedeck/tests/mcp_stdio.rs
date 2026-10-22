//! Integração: handshake MCP pelo binário real.

use serde_json::{Value, json};
use std::io::Write;
use std::process::{Command, Stdio};

fn project() -> tempdir::Dir {
    tempdir::Dir::new()
}

mod tempdir {
    pub struct Dir(pub std::path::PathBuf);
    impl Dir {
        pub fn new() -> Self {
            let p = std::env::temp_dir().join(
                format!(
                    "vibedeck-it-{}-{:?}",
                    std::process::id(),
                    std::thread::current().id()
                )
                .replace(['(', ')', ' '], ""),
            );
            std::fs::create_dir_all(&p).unwrap();
            std::fs::write(p.join("vibedeck.json"), "{}").unwrap();
            Dir(p)
        }
    }
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

fn run(args: &[&str], dir: &std::path::Path, input: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .args(args)
        .current_dir(dir)
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

#[test]
fn handshake_completo_sai_0_no_eof() {
    let p = project();
    let msgs = [
        json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
        json!({"jsonrpc":"2.0","method":"notifications/initialized"}),
        json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
        json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nao_existe","arguments":{}}}),
        json!({"jsonrpc":"2.0","id":4,"method":"ping"}),
        json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}),
        json!({"jsonrpc":"2.0","id":5,"method":"resources/list"}),
        json!({"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"vibedeck://nada"}}),
        json!({"jsonrpc":"2.0","id":7,"method":"foo/bar"}),
    ];
    let input: String = msgs.iter().map(|m| format!("{m}\n")).collect();
    let (code, stdout, stderr) = run(&["mcp"], &p.0, &input);
    assert_eq!(code, 0, "stderr: {stderr}");
    let replies: Vec<Value> = stdout
        .lines()
        .map(|l| serde_json::from_str(l).expect("stdout só tem JSON-RPC"))
        .collect();
    assert!(replies.iter().all(|r| r["jsonrpc"] == "2.0"));
    assert_eq!(replies.len(), 7); // 2 notificações sem resposta
    let init = &replies[0]["result"];
    assert_eq!(init["protocolVersion"], "2024-11-05");
    assert_eq!(init["serverInfo"]["name"], "vibedeck");
    assert!(init["instructions"].as_str().unwrap().contains("rules_for"));
    assert!(replies[1]["result"]["tools"].is_array());
    assert_eq!(replies[2]["result"]["isError"], true);
    assert_eq!(replies[3]["result"], json!({}));
    assert_eq!(replies[4]["result"]["resources"], json!([]));
    assert!(replies[5]["error"]["code"].is_i64());
    assert_eq!(replies[6]["error"]["code"], -32601);
}

#[test]
fn eof_imediato_e_linha_invalida() {
    let p = project();
    let (code, out, _) = run(&["mcp", "serve"], &p.0, "");
    assert_eq!((code, out.as_str()), (0, ""));
    let (code, out, _) = run(&["mcp"], &p.0, "isto nao e json\n\n");
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(v["error"]["code"], -32700);
    assert_eq!(v["id"], Value::Null);
}

#[test]
fn flag_c_global_e_erros_de_cli() {
    let p = project();
    let other = std::env::temp_dir();
    let dir = p.0.to_str().unwrap();
    let (code, out, _) = run(
        &["-C", dir, "mcp"],
        &other,
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n",
    );
    assert_eq!(code, 0);
    assert!(out.contains("\"result\""));
    let (code, _, err) = run(&["-C", "/nonexistent-vibedeck-dir", "mcp"], &other, "");
    assert_eq!(code, 1);
    assert!(err.contains("Nenhum vibedeck.json encontrado"));
    let (code, _, _) = run(&["bogus"], &other, "");
    assert_eq!(code, 64);
}
