//! Integração: CLI `workflows`/`runs` e tools MCP de workflows pelo binário real.

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use vibedeck_core::Store;
use vibedeck_core::model::Agent;

struct Proj(PathBuf);
impl Proj {
    fn new(name: &str) -> Self {
        let p = std::env::temp_dir().join(format!("vibedeck-wf-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        let store = Store::init(&p, "teste", None).unwrap();
        store.create(&Agent::new("Revisor"), None).unwrap();
        Proj(p)
    }
}
impl Drop for Proj {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn run(args: &[&str], dir: &Path, input: &str) -> (i32, String, String) {
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

fn ok(args: &[&str], p: &Proj, input: &str) -> String {
    let (code, out, err) = run(args, &p.0, input);
    assert_eq!(code, 0, "{args:?}: {err}");
    out
}

#[test]
fn cli_fluxo_completo() {
    let p = Proj::new("cli");
    let slug = ok(&["workflows", "new", "Revisão de PR"], &p, "");
    assert_eq!(slug.trim(), "revisao-de-pr");
    ok(&["workflows", "step", "revisao-de-pr", "Revisor"], &p, "");
    let list = ok(&["workflows", "--json"], &p, "");
    let _: Value = serde_json::from_str(&list).unwrap_or_else(|_| {
        serde_json::from_str(&ok(&["workflows", "list", "--json"], &p, "")).unwrap()
    });
    let show = ok(&["workflows", "show", "revisao-de-pr"], &p, "");
    assert!(show.contains("Revisão de PR"));

    let start = ok(
        &["runs", "start", "revisao-de-pr", "--input", "42", "--json"],
        &p,
        "",
    );
    let v: Value = serde_json::from_str(&start).unwrap();
    let r = v["run"].as_str().unwrap().to_string();
    let step = ok(&["runs", "step", &r], &p, "");
    assert!(step.contains("Revisor"));
    let next = ok(&["runs", "next", &r, "--json"], &p, "");
    assert!(serde_json::from_str::<Value>(&next).is_ok());
    ok(&["runs", "record", &r, "--summary", "ok"], &p, "");
    let show = ok(&["runs", "show", &r, "--json"], &p, "");
    assert_eq!(
        serde_json::from_str::<Value>(&show).unwrap()["status"],
        "done"
    );
    ok(&["runs", "delete", &r], &p, "");
    let (code, _, _) = run(&["runs", "show", &r], &p.0, "");
    assert_ne!(code, 0);
}

#[test]
fn cli_perguntas_e_retomada() {
    let p = Proj::new("ask");
    ok(&["workflows", "new", "Fluxo"], &p, "");
    ok(&["workflows", "step", "fluxo", "Revisor"], &p, "");
    let start = ok(&["runs", "start", "fluxo", "--json"], &p, "");
    let r = serde_json::from_str::<Value>(&start).unwrap()["run"]
        .as_str()
        .unwrap()
        .to_string();
    let qs = r#"[{"question":"Qual?","options":[{"label":"A"},{"label":"B"}]}]"#;
    ok(&["runs", "ask", &r], &p, qs);
    let open = ok(&["runs", "questions", &r, "--open", "--json"], &p, "");
    assert_eq!(
        serde_json::from_str::<Value>(&open).unwrap()[0]["question"],
        "Qual?"
    );
    ok(&["runs", "answer", &r, "1", "A"], &p, "");
    let open = ok(&["runs", "questions", &r, "--open", "--json"], &p, "");
    assert_eq!(serde_json::from_str::<Value>(&open).unwrap(), json!([]));
    ok(&["runs", "stop", &r, "--reason", "teste"], &p, "");
    let list = ok(&["runs", "--status", "stopped", "--json"], &p, "");
    assert_eq!(
        serde_json::from_str::<Value>(&list)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

fn mcp(p: &Proj, calls: &[(&str, Value)]) -> Vec<Value> {
    let mut input = String::new();
    for (i, (name, args)) in calls.iter().enumerate() {
        input += &format!(
            "{}\n",
            json!({"jsonrpc":"2.0","id":i+1,"method":"tools/call","params":{"name":name,"arguments":args}})
        );
    }
    let (code, out, err) = run(&["mcp"], &p.0, &input);
    assert_eq!(code, 0, "{err}");
    out.lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

fn text(r: &Value) -> &str {
    r["result"]["content"][0]["text"].as_str().unwrap()
}

#[test]
fn mcp_workflow_e_run() {
    let p = Proj::new("mcp");
    let r = mcp(
        &p,
        &[
            ("add_workflow", json!({"title": "Fluxo X"})),
            (
                "add_workflow_step",
                json!({"workflow":"fluxo-x","target":"Revisor","max_visits":2}),
            ),
            ("list_workflows", json!({})),
            ("workflow_flow", json!({"workflow":"fluxo-x"})),
            (
                "workflow_run_start",
                json!({"workflow":"fluxo-x","input":"1"}),
            ),
            ("get_workflow", json!({})),
            (
                "set_workflow_step_max_visits",
                json!({"workflow":"fluxo-x","step":"1"}),
            ),
        ],
    );
    assert_eq!(r.len(), 7);
    assert_eq!(
        serde_json::from_str::<Value>(text(&r[0])).unwrap()["slug"],
        "fluxo-x"
    );
    let added: Value = serde_json::from_str(text(&r[1])).unwrap();
    assert!(added["step"].is_string());
    let list: Value = serde_json::from_str(text(&r[2])).unwrap();
    assert_eq!(list[0]["steps"].as_array().unwrap().len(), 1);
    let start: Value = serde_json::from_str(text(&r[4])).unwrap();
    let rf = start["ref"].as_str().unwrap().to_string();
    assert!(start["prompt"].is_string());
    assert_eq!(r[5]["result"]["isError"], true);
    assert_eq!(r[6]["result"]["isError"], true);
    assert!(text(&r[6]).contains("max_visits"));

    let r = mcp(
        &p,
        &[
            ("workflow_run_step", json!({"run": rf})),
            ("workflow_run_next", json!({"run": rf})),
            (
                "workflow_run_record",
                json!({"run": rf, "summary": "feito"}),
            ),
            ("workflow_run_list", json!({"status":"done"})),
            ("workflow_run_show", json!({"run": rf})),
        ],
    );
    assert!(text(&r[0]).contains("Revisor"));
    assert_eq!(
        serde_json::from_str::<Value>(text(&r[3]))
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        serde_json::from_str::<Value>(text(&r[4])).unwrap()["status"],
        "done"
    );
}
