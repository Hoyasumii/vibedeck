//! Integração do início guiado: CLI `onboarding` e tools MCP pelo binário real.

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static N: AtomicUsize = AtomicUsize::new(0);

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "vd-onb-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&p).unwrap();
        Dir(p)
    }
    fn path(&self) -> &Path {
        &self.0
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn write(root: &Path, rel: &str, text: &str) {
    let p = root.join(rel);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, text).unwrap();
}

fn project() -> Dir {
    let d = Dir::new();
    write(d.path(), "vibedeck.json", r#"{"name":"demo"}"#);
    write(
        d.path(),
        ".claude/agents/reviewer.md",
        "---\nname: reviewer\ndescription: Revisa\n---\nRevise.",
    );
    write(
        d.path(),
        ".claude/skills/deploy/SKILL.md",
        "---\nname: deploy\ndescription: Deploy\n---\nDeploy.",
    );
    write(d.path(), ".codex/prompts/plan.md", "Planeje.");
    d
}

fn run(args: &[&str], dir: &Path, input: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .args(args)
        .current_dir(dir)
        .env("HOME", dir.join("home"))
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
    let o = child.wait_with_output().unwrap();
    (
        o.status.code().unwrap(),
        String::from_utf8(o.stdout).unwrap(),
        String::from_utf8(o.stderr).unwrap(),
    )
}

fn count(dir: &Path, sub: &str) -> usize {
    std::fs::read_dir(dir.join(".vibedeck").join(sub))
        .map(|r| {
            r.filter_map(|e| e.ok())
                .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
                .count()
        })
        .unwrap_or(0)
}

fn mcp(dir: &Path, calls: &[(&str, Value)]) -> Vec<(bool, String)> {
    let mut input = json!({"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}).to_string() + "\n";
    for (i, (name, args)) in calls.iter().enumerate() {
        input += &json!({"jsonrpc":"2.0","id":i + 1,"method":"tools/call","params":{"name":name,"arguments":args}}).to_string();
        input += "\n";
    }
    let (code, out, err) = run(&["mcp"], dir, &input);
    assert_eq!(code, 0, "{err}");
    out.lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .filter(|v| v["id"].as_i64().unwrap_or(0) > 0)
        .map(|v| {
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
fn cli_status_texto_e_json() {
    let d = project();
    let (code, out, _) = run(&["onboarding"], d.path(), "");
    assert_eq!(code, 0);
    assert!(out.contains("Início guiado: pendente"), "{out}");
    assert!(out.contains("agent:reviewer"), "{out}");
    let (code, out, _) = run(&["onboarding", "--json"], d.path(), "");
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["status"], "pending");
    assert_eq!(v["shouldPrompt"], true);
    assert_eq!(v["resources"].as_array().unwrap().len(), 3);
    let (_, out, _) = run(&["onboarding", "status", "--json"], d.path(), "");
    assert_eq!(
        serde_json::from_str::<Value>(&out).unwrap()["step"],
        "stack"
    );
}

#[test]
fn cli_pasta_sem_projeto_lista_sem_escrever() {
    let d = Dir::new();
    write(d.path(), ".claude/agents/a.md", "---\nname: a\n---\nx");
    let (code, out, _) = run(&["onboarding", "--json"], d.path(), "");
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["hasProject"], false);
    assert_eq!(v["resources"].as_array().unwrap().len(), 1);
    assert!(!d.path().join(".vibedeck").exists());
}

#[test]
fn cli_skip_nao_cria_registros_e_import_nao_duplica() {
    let d = project();
    let (code, _, _) = run(&["onboarding", "skip"], d.path(), "");
    assert_eq!(code, 0);
    assert_eq!(
        count(d.path(), "agents") + count(d.path(), "skills") + count(d.path(), "commands"),
        0
    );
    let (_, out, _) = run(&["onboarding", "--json"], d.path(), "");
    assert_eq!(
        serde_json::from_str::<Value>(&out).unwrap()["status"],
        "skipped"
    );

    let (code, out, _) = run(&["onboarding", "import", "agent:reviewer"], d.path(), "");
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("cadastrado: agent:reviewer"));
    assert_eq!(count(d.path(), "agents"), 1);
    assert_eq!(count(d.path(), "skills"), 0);
    let (_, out, _) = run(
        &["onboarding", "import", "agent:reviewer", "--json"],
        d.path(),
        "",
    );
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["imported"], json!([]));
    assert_eq!(v["alreadyRegistered"], json!(["agent:reviewer"]));
    assert_eq!(count(d.path(), "agents"), 1);

    let (code, _, err) = run(&["onboarding", "import", "skill:nada"], d.path(), "");
    assert_ne!(code, 0);
    assert!(err.contains("não encontrado"), "{err}");
    let (code, _, _) = run(&["onboarding", "complete"], d.path(), "");
    assert_eq!(code, 0);
    let (_, out, _) = run(&["onboarding", "--json"], d.path(), "");
    assert_eq!(
        serde_json::from_str::<Value>(&out).unwrap()["status"],
        "done"
    );
}

#[test]
fn mcp_status_apply_e_erros() {
    let d = project();
    let r = mcp(
        d.path(),
        &[
            ("onboarding_status", json!({})),
            ("onboarding_apply", json!({"action":"skip"})),
            (
                "onboarding_apply",
                json!({"action":"import","items":["skill:deploy","command:plan"]}),
            ),
            (
                "onboarding_apply",
                json!({"action":"import","items":["skill:deploy"]}),
            ),
            (
                "onboarding_apply",
                json!({"action":"import","items":["agent:x"]}),
            ),
            ("onboarding_apply", json!({"action":"import"})),
            ("onboarding_apply", json!({"action":"zzz"})),
            ("onboarding_apply", json!({"action":"complete"})),
        ],
    );
    assert!(!r[0].0);
    assert_eq!(
        serde_json::from_str::<Value>(&r[0].1).unwrap()["status"],
        "pending"
    );
    assert!(!r[1].0);
    let imp: Value = serde_json::from_str(&r[2].1).unwrap();
    assert_eq!(imp["imported"], json!(["skill:deploy", "command:plan"]));
    let dup: Value = serde_json::from_str(&r[3].1).unwrap();
    assert_eq!(dup["imported"], json!([]));
    assert_eq!(dup["alreadyRegistered"], json!(["skill:deploy"]));
    assert!(r[4].0 && r[5].0 && r[6].0);
    assert!(!r[7].0);
    assert_eq!(count(d.path(), "agents"), 0);
    assert_eq!(count(d.path(), "skills"), 1);
}
