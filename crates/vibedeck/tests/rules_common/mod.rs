//! Utilitários dos testes de integração da área `rules` (projeto temporário + binário real).
#![allow(dead_code)]

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

pub struct Project(pub PathBuf);

impl Project {
    pub fn new() -> Self {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("vibedeck-rules-it-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("vibedeck.json"), "{}").unwrap();
        Project(dir)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }

    pub fn cli(&self, args: &[&str]) -> (i32, String, String) {
        self.cli_in(&self.0, args, "")
    }

    pub fn cli_in(&self, cwd: &Path, args: &[&str], input: &str) -> (i32, String, String) {
        run_bin(args, cwd, input, &[])
    }

    /// Chama uma tool pelo servidor MCP real; devolve `(isError, texto)`.
    pub fn tool(&self, name: &str, arguments: Value) -> (bool, String) {
        let msgs = [
            json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
            json!({"jsonrpc":"2.0","method":"notifications/initialized"}),
            json!({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":name,"arguments":arguments}}),
        ];
        let input: String = msgs.iter().map(|m| format!("{m}\n")).collect();
        let (code, out, err) = run_bin(&["mcp"], &self.0, &input, &[]);
        assert_eq!(code, 0, "{err}");
        let reply: Value = out
            .lines()
            .filter_map(|l| serde_json::from_str::<Value>(l).ok())
            .find(|v| v["id"] == 2)
            .expect("resposta do tools/call");
        let result = &reply["result"];
        (
            result["isError"].as_bool().unwrap_or(false),
            result["content"][0]["text"]
                .as_str()
                .unwrap_or("")
                .to_string(),
        )
    }

    pub fn tools_list(&self) -> Vec<Value> {
        let msgs = [
            json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
            json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
        ];
        let input: String = msgs.iter().map(|m| format!("{m}\n")).collect();
        let (_, out, _) = run_bin(&["mcp"], &self.0, &input, &[]);
        let reply: Value = out
            .lines()
            .filter_map(|l| serde_json::from_str::<Value>(l).ok())
            .find(|v| v["id"] == 2)
            .unwrap();
        reply["result"]["tools"].as_array().unwrap().clone()
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub fn run_bin(
    args: &[&str],
    cwd: &Path,
    input: &str,
    env: &[(&str, &str)],
) -> (i32, String, String) {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_vibedeck"));
    cmd.args(args)
        .current_dir(cwd)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (k, v) in env {
        cmd.env(k, v);
    }
    let mut child = cmd.spawn().unwrap();
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
