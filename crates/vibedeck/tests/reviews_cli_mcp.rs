//! Integração do binário: `vibedeck review ...` e tools MCP de revisão.

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

struct Dir(PathBuf);

impl Dir {
    fn new(tag: &str) -> Self {
        let p = std::env::temp_dir().join(format!("vibedeck-reviews-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        std::fs::write(p.join("vibedeck.json"), r#"{"name":"demo"}"#).unwrap();
        Dir(p)
    }
}

impl Drop for Dir {
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

fn cli(dir: &Dir, args: &[&str]) -> (i32, String, String) {
    run(args, &dir.0, "")
}

/// Chama uma tool pelo MCP e devolve `(isError, texto)`.
fn tool(dir: &Dir, name: &str, args: Value) -> (bool, String) {
    let input = format!(
        "{}\n{}\n",
        json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
        json!({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":name,"arguments":args}}),
    );
    let (code, out, err) = run(&["mcp"], &dir.0, &input);
    assert_eq!(code, 0, "{err}");
    let reply: Value = serde_json::from_str(out.lines().nth(1).unwrap()).unwrap();
    let r = &reply["result"];
    (
        r["isError"] == true,
        r["content"][0]["text"].as_str().unwrap().to_string(),
    )
}

fn add_topic_with_manual_rule(dir: &Dir) {
    std::fs::create_dir_all(dir.0.join(".vibedeck/rules")).unwrap();
    std::fs::write(
        dir.0.join(".vibedeck/rules/api.json"),
        r#"{"id":"11111111-1111-1111-1111-111111111111","title":"API","author":"human","paths":["src/api/**"],"rules":[{"id":"22222222-2222-2222-2222-222222222222","text":"Valide entrada","severity":"must","author":"human","createdAt":"2026-01-01T00:00:00Z"}],"createdAt":"2026-01-01T00:00:00Z"}"#,
    )
    .unwrap();
}

#[test]
fn cli_add_list_set_remove() {
    let d = Dir::new("cli");
    let (code, out, err) = cli(
        &d,
        &[
            "review",
            "add",
            "Tela de Login",
            "Inativar botão",
            "--kind",
            "disable",
            "--file",
            "a.rs",
            "--route",
            "/login",
            "--priority",
            "high",
            "--ai",
        ],
    );
    assert_eq!(code, 0, "{err}");
    let (id, slug) = out.trim().split_once('\t').unwrap();
    assert_eq!(id.len(), 36);
    assert_eq!(slug, "tela-de-login");
    let id8 = &id[..8];

    // padrão = list
    let (code, out, _) = cli(&d, &["review"]);
    assert_eq!(code, 0);
    assert_eq!(
        out,
        format!("\n## tela-de-login\n{id8}  [open] (disable) Inativar botão  → a.rs /login\n")
    );
    let (_, out2, _) = cli(
        &d,
        &["review", "list", "--status", "open", "--kind", "disable"],
    );
    assert_eq!(out2, out);
    let (_, empty, _) = cli(&d, &["review", "--status", "done"]);
    assert_eq!(empty, "");

    // groups
    let (_, out, _) = cli(&d, &["review", "groups"]);
    assert_eq!(out, "tela-de-login\tTela de Login\t1/1\n");
    let (_, out, _) = cli(&d, &["review", "groups", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["slug"], "tela-de-login");
    assert_eq!(v[0]["group"], "");
    assert_eq!(v[0]["items"][0]["author"], "ai");
    assert_eq!(v[0]["items"][0]["priority"], "high");

    // list --json
    let (_, out, _) = cli(
        &d,
        &["review", "list", "--json", "--group", "Tela de Login"],
    );
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["group"], "tela-de-login");
    assert_eq!(v[0]["item"]["target"]["file"], "a.rs");
    assert_eq!(v[0]["item"]["id"], id);

    // set
    let (code, out, _) = cli(
        &d,
        &[
            "review",
            "set",
            id8,
            "--status",
            "in_progress",
            "--title",
            "Novo",
        ],
    );
    assert_eq!(code, 0);
    assert_eq!(out, format!("{id8}  [in_progress] Novo\n"));
    let (code, out, _) = cli(
        &d,
        &["review", "set", &id.to_lowercase(), "--status", "done"],
    );
    assert_eq!(code, 0);
    assert_eq!(out, format!("{id8}  [done] Novo\n"));
    let (_, out, _) = cli(&d, &["review", "groups"]);
    assert_eq!(out, "tela-de-login\tTela de Login\t0/1\n");

    // remove
    let (code, out, _) = cli(&d, &["review", "remove", id8]);
    assert_eq!((code, out.as_str()), (0, ""));
    let (code, _, err) = cli(&d, &["review", "remove", id8]);
    assert_eq!(code, 1);
    assert!(err.contains("Item de revisão não encontrado"));
}

#[test]
fn cli_erros() {
    let d = Dir::new("cli-err");
    let (code, _, err) = cli(&d, &["review", "add", "g", "t", "--kind", "zzz"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "Error: Kind desconhecido 'zzz'. Disponíveis: disable, hide, fix, change, remove, note\n"
    );
    let (code, _, _) = cli(&d, &["review", "set", "abcd", "--status", "feito"]);
    assert_eq!(code, 64);
    let (code, _, err) = cli(&d, &["review", "list", "--group", "nada"]);
    assert_eq!(code, 1);
    assert!(err.contains("Grupo de revisão não encontrado: nada"));
    let (code, _, err) = cli(&d, &["review", "add", "g", "t", "--rules", "inexistente"]);
    assert_eq!(code, 1);
    assert!(err.contains("Tópico de regras não encontrado: inexistente"));
}

#[test]
fn cli_gate_e_force() {
    let d = Dir::new("cli-gate");
    add_topic_with_manual_rule(&d);
    let (_, out, _) = cli(
        &d,
        &["review", "add", "G", "Endpoint", "--file", "src/api/x.rs"],
    );
    let id = out.split('\t').next().unwrap().to_string();
    let (code, _, err) = cli(&d, &["review", "set", &id, "--status", "done"]);
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: O item não pode ser concluído sem passar pelas regras:\n- Nenhum check registrado para este item (tópicos: api)."));
    let (_, out, _) = cli(&d, &["review", "list", "--status", "open"]);
    assert!(out.contains("[open]"));
    let (code, out, _) = cli(&d, &["review", "set", &id, "--status", "done", "--force"]);
    assert_eq!(code, 0);
    assert!(out.contains("[done]"));
}

#[test]
fn cli_add_com_regras_multiplas() {
    let d = Dir::new("cli-rules");
    add_topic_with_manual_rule(&d);
    let (code, out, err) = cli(&d, &["review", "add", "G", "x", "--rules", "api", "API"]);
    assert_eq!(code, 0, "{err}");
    let id = out.split('\t').next().unwrap();
    let (_, out, _) = cli(&d, &["review", "list", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["item"]["rules"], json!(["api", "api"]));
    let (code, _, _) = cli(&d, &["review", "set", id, "--rules", "api"]);
    assert_eq!(code, 0);
}

#[test]
fn mcp_fluxo_completo() {
    let d = Dir::new("mcp");
    let (err, text) = tool(
        &d,
        "add_review_item",
        json!({"group":"Tela","kind":"fix","title":"Botão","file":"a.rs","priority":"high","details":"d"}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["group"], "tela");
    assert_eq!(v["item"]["author"], "ai");
    assert_eq!(v["item"]["priority"], "high");
    assert_eq!(v["item"]["status"], "open");
    let id = v["item"]["id"].as_str().unwrap().to_string();

    let (err, text) = tool(&d, "list_review_groups", json!({}));
    assert!(!err);
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(
        v,
        json!([{"group":"","slug":"tela","title":"Tela","tags":[],"open":1,"total":1}])
    );

    let (_, text) = tool(
        &d,
        "list_review_items",
        json!({"status":"open","kind":"fix"}),
    );
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v[0]["group"], "tela");
    assert_eq!(v[0]["item"]["id"], id);
    let (_, text) = tool(&d, "list_review_items", json!({"status":"done"}));
    assert_eq!(serde_json::from_str::<Value>(&text).unwrap(), json!([]));
    // status desconhecido não filtra
    let (_, text) = tool(&d, "list_review_items", json!({"status":"zzz"}));
    assert_eq!(
        serde_json::from_str::<Value>(&text)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );

    let (err, text) = tool(
        &d,
        "update_review_item",
        json!({"id":&id[..8],"status":"done","title":"Novo"}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["status"], "done");
    assert_eq!(v["title"], "Novo");

    let (err, text) = tool(&d, "update_review_item", json!({"id":id,"status":"feito"}));
    assert!(err);
    assert_eq!(text, "Invalid params: Status inválido: feito");
    let (err, text) = tool(&d, "update_review_item", json!({"id":id,"kind":"zzz"}));
    assert!(err);
    assert!(text.starts_with("Invalid params: Kind desconhecido 'zzz'. Disponíveis: disable"));
    let (err, text) = tool(&d, "update_review_item", json!({"id":"deadbeef"}));
    assert!(err);
    assert_eq!(text, "Item de revisão não encontrado: deadbeef");
}

#[test]
fn mcp_erros_e_gate() {
    let d = Dir::new("mcp-gate");
    add_topic_with_manual_rule(&d);
    let (err, text) = tool(
        &d,
        "add_review_item",
        json!({"group":"G","kind":"zzz","title":"x"}),
    );
    assert!(err);
    assert!(text.starts_with("Invalid params: Kind desconhecido 'zzz'."));
    let (err, text) = tool(&d, "add_review_item", json!({"group":"G","kind":"fix"}));
    assert!(err);
    assert_eq!(text, "Invalid params: Parâmetro obrigatório: title");
    let (err, text) = tool(&d, "list_review_items", json!({"group":"nada"}));
    assert!(err);
    assert_eq!(text, "Grupo de revisão não encontrado: nada");

    let (_, text) = tool(
        &d,
        "add_review_item",
        json!({"group":"G","kind":"fix","title":"x","rules":"api"}),
    );
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["item"]["rules"], json!(["api"]));
    let id = v["item"]["id"].as_str().unwrap();
    let (err, text) = tool(&d, "update_review_item", json!({"id":id,"status":"done"}));
    assert!(err);
    assert!(text.starts_with("O item não pode ser concluído sem passar pelas regras:\n- "));
    assert!(text.ends_with("com o id do item."));
    // limpar as regras via [] e concluir: o tópico `api` casa só src/api/**, sem alvo não há regra no escopo
    let (err, text) = tool(
        &d,
        "update_review_item",
        json!({"id":id,"rules":[],"status":"done"}),
    );
    assert!(!err, "{text}");
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["status"], "done");
    assert!(v.get("rules").is_none());
}

#[test]
fn mcp_listagem_de_tools() {
    let d = Dir::new("mcp-list");
    let input = format!(
        "{}\n",
        json!({"jsonrpc":"2.0","id":1,"method":"tools/list"})
    );
    let (_, out, _) = run(&["mcp"], &d.0, &input);
    let reply: Value = serde_json::from_str(out.lines().next().unwrap()).unwrap();
    let tools = reply["result"]["tools"].as_array().unwrap();
    let find = |n: &str| tools.iter().find(|t| t["name"] == n).unwrap().clone();
    let g = find("list_review_groups");
    assert_eq!(g["description"], "Grupos com itens abertos.");
    assert_eq!(g["inputSchema"], json!({"type":"object"}));
    assert_eq!(g["annotations"]["readOnlyHint"], true);
    let l = find("list_review_items");
    assert_eq!(l["description"], "");
    assert_eq!(
        l["inputSchema"]["properties"]["status"]["enum"],
        json!(["open", "in_progress", "done", "wontfix"])
    );
    let a = find("add_review_item");
    assert_eq!(
        a["inputSchema"]["required"],
        json!(["group", "kind", "title"])
    );
    assert_eq!(
        a["inputSchema"]["properties"]["rules"]["items"],
        json!({"type":"string"})
    );
    assert!(a.get("annotations").is_none());
    let u = find("update_review_item");
    assert_eq!(u["inputSchema"]["required"], json!(["id"]));
}
