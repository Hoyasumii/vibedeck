//! Integração do binário: CLI `docs`/`groups` e tools MCP de Docs e grupos.

use serde_json::{Value, json};
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

struct Dir(std::path::PathBuf);
impl Dir {
    fn path(&self) -> &Path {
        &self.0
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn project() -> Dir {
    static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let p = std::env::temp_dir().join(format!("vibedeck-docs-it-{}-{n}", std::process::id()));
    std::fs::create_dir_all(&p).unwrap();
    std::fs::write(p.join("vibedeck.json"), "{}").unwrap();
    Dir(p)
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

fn mcp(dir: &Path, calls: &[(&str, Value)]) -> Vec<Value> {
    let mut input = String::new();
    for (i, (name, args)) in calls.iter().enumerate() {
        input += &format!(
            "{}\n",
            json!({"jsonrpc":"2.0","id":i+1,"method":"tools/call","params":{"name":name,"arguments":args}})
        );
    }
    let (code, out, err) = run(&["mcp"], dir, &input);
    assert_eq!(code, 0, "{err}");
    out.lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap()["result"].clone())
        .collect()
}

fn text(v: &Value) -> &str {
    v["content"][0]["text"].as_str().unwrap()
}

#[test]
fn cli_docs_ciclo_basico() {
    let p = project();
    let d = p.path();
    let (c, out, _) = run(&["docs", "new", "Guia Rápido", "--body", "oi"], d, "");
    assert_eq!((c, out.as_str()), (0, "guia-rapido\n"));
    let (_, out, _) = run(&["docs"], d, "");
    assert_eq!(out, "guia-rapido\tGuia Rápido\n");
    let (_, out, _) = run(&["docs", "cat", "guia-rapido"], d, "");
    assert_eq!(out, "# Guia Rápido\n\noi");
    run(&["docs", "write", "guia-rapido"], d, "# Outro\n");
    let (_, out, _) = run(&["docs", "list", "--json"], d, "");
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["title"], "Outro");
    assert_eq!(v[0]["group"], "");
    assert!(v[0].get("linked").is_none());
    let (c, _, err) = run(&["docs", "cat", "nao-existe"], d, "");
    assert_ne!(c, 0);
    assert!(!err.is_empty());
}

#[cfg(unix)]
#[test]
fn cli_e_mcp_docs_vinculados() {
    let p = project();
    let d = p.path();
    std::fs::write(d.join("README.md"), "# Leia-me\n\ncorpo\n").unwrap();
    let (_, out, _) = run(&["docs", "--json"], d, "");
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["slug"], "readme");
    assert_eq!(v[0]["linked"], true);
    assert_eq!(v[0]["target"], "README.md");
    let (_, out, _) = run(&["docs", "list"], d, "");
    assert_eq!(out, "readme\tLeia-me → README.md\n");
    let r = mcp(
        d,
        &[
            ("list_docs", json!({})),
            ("write_doc", json!({"slug":"readme","content":"# Novo\n"})),
            ("read_doc", json!({"slug":"readme"})),
        ],
    );
    let rows: Value = serde_json::from_str(text(&r[0])).unwrap();
    assert_eq!(rows[0]["linked"], true);
    assert_eq!(text(&r[1]), "Salvo: readme");
    assert_eq!(text(&r[2]), "# Novo\n");
    assert_eq!(
        std::fs::read_to_string(d.join("README.md")).unwrap(),
        "# Novo\n"
    );
    assert!(
        std::fs::symlink_metadata(d.join(".vibedeck/docs/readme.md"))
            .unwrap()
            .file_type()
            .is_symlink()
    );
    // quebrar a origem: aviso no stderr e unlink remove só o link
    std::fs::remove_file(d.join("README.md")).unwrap();
    let (c, _, err) = run(&["docs"], d, "");
    assert_eq!(c, 0);
    assert!(err.contains("quebrado"));
    let (c, _, _) = run(&["docs", "unlink", "readme"], d, "");
    assert_eq!(c, 0);
    assert!(std::fs::symlink_metadata(d.join(".vibedeck/docs/readme.md")).is_err());
}

#[test]
fn cli_e_mcp_grupos() {
    let p = project();
    let d = p.path();
    run(&["docs", "new", "Alfa", "--reference", "area/alfa"], d, "");
    let (_, out, _) = run(&["groups", "list", "docs", "--json"], d, "");
    assert!(out.contains("area"));
    let (c, out, _) = run(&["groups", "create", "docs", "outro"], d, "");
    assert_eq!((c, out.trim()), (0, "outro"));
    let (c, out, _) = run(
        &["groups", "move-item", "docs", "area/alfa", "outro"],
        d,
        "",
    );
    assert_eq!(c, 0, "{out}");
    assert!(d.join(".vibedeck/docs/outro/alfa.md").exists());
    let r = mcp(
        d,
        &[
            (
                "item_groups",
                json!({"concept":"docs","action":"move_item","reference":"alfa","to":"novo"}),
            ),
            ("item_groups", json!({"concept":"docs","action":"list"})),
            (
                "item_groups",
                json!({"concept":"docs","action":"delete","path":"outro"}),
            ),
            ("move_rule_to_group", json!({"rule":"zzz","group":"g"})),
        ],
    );
    assert!(d.join(".vibedeck/docs/novo/alfa.md").exists(), "{r:?}");
    assert!(
        r[1]["content"][0]["text"]
            .as_str()
            .unwrap()
            .starts_with('[')
    );
    assert_eq!(text(&r[2]), "Grupo apagado.");
    assert_eq!(r[3]["isError"], true);
}
