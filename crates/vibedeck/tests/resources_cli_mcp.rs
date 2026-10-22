//! Integração da área resources: CLI (`agents|commands|skills|kits`) e tools MCP pelo binário real.

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
            "vd-res-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
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
    let out = child.wait_with_output().unwrap();
    (
        out.status.code().unwrap(),
        String::from_utf8(out.stdout).unwrap(),
        String::from_utf8(out.stderr).unwrap(),
    )
}

fn cli(dir: &Path, args: &[&str]) -> (i32, String, String) {
    run(args, dir, "")
}

/// Chama tools em sequência numa só sessão MCP; devolve `(isError, texto)` de cada chamada.
fn mcp(dir: &Path, calls: &[(&str, Value)]) -> Vec<(bool, String)> {
    let mut input = String::new();
    input += &json!({"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}).to_string();
    input += "\n";
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
fn cli_agentes_fluxo_completo() {
    let d = Dir::new();
    let p = &d.0;
    let (c, out, _) = cli(
        p,
        &[
            "agents",
            "new",
            "Revisor Geral",
            "--model",
            "opus",
            "--summary",
            "Revisa",
        ],
    );
    assert_eq!((c, out.trim()), (0, "revisor-geral"));
    cli(p, &["agents", "new", "Testador"]);
    let (c, out, _) = cli(
        p,
        &[
            "agents",
            "next",
            "revisor-geral",
            "testador",
            "--note",
            "depois",
        ],
    );
    assert_eq!((c, out.trim()), (0, "revisor-geral\t1 passo(s)"));
    let (_, out, _) = cli(p, &["agents", "flow", "revisor-geral"]);
    assert!(out.contains("testador"));
    let (_, out, _) = cli(p, &["agents", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v.as_array().unwrap().len(), 2);
    let (c, _, e) = cli(p, &["agents", "next", "revisor-geral", "revisor-geral"]);
    assert_ne!(c, 0);
    assert!(e.contains("Próximo passo inválido"));
    let (c, _, _) = cli(p, &["agents", "unnext", "revisor-geral", "testador"]);
    assert_eq!(c, 0);
    assert!(p.join(".vibedeck/agents/revisor-geral.json").exists());
}

#[test]
fn cli_kits_listar_e_adicionar() {
    let d = Dir::new();
    let (c, out, _) = cli(&d.0, &["kits", "list", "--json"]);
    assert_eq!(c, 0);
    let kits: Value = serde_json::from_str(&out).unwrap();
    let kit = &kits.as_array().unwrap()[0];
    let item = kit["items"][0]["id"].as_str().unwrap().to_string();
    let (c, out, err) = cli(&d.0, &["kits", "add", &item]);
    // Itens com dependências exigem selecionar também as dependências.
    if c == 0 {
        assert!(out.contains(':'));
    } else {
        assert!(err.contains("Selecione também as dependências"), "{err}");
    }
    let (c, _, err) = cli(&d.0, &["kits", "add", "nao-existe"]);
    assert_ne!(c, 0);
    assert!(err.contains("Seleção de kit inválida"));
}

#[test]
fn mcp_agentes_comandos_skills() {
    let d = Dir::new();
    let r = mcp(
        &d.0,
        &[
            (
                "add_agent",
                json!({"title":"Revisor","summary":"Revisa","tools":["Read"],"provider_settings":{"codex":{"model":"gpt"}}}),
            ),
            (
                "add_command",
                json!({"title":"Deploy","argument_hint":"ambiente"}),
            ),
            (
                "add_skill",
                json!({"title":"Lint","reference":"qualidade/lint"}),
            ),
            (
                "add_agent_next_step",
                json!({"agent":"revisor","target":"deploy","kind":"command"}),
            ),
            (
                "update_command",
                json!({"command":"deploy","summary":"Publica","tags":"a,b"}),
            ),
            ("get_agent", json!({"agent":"revisor"})),
            ("list_agents", json!({})),
            ("list_skills", json!({})),
            ("agent_flow", json!({"agent":"revisor"})),
            (
                "add_agent_next_step",
                json!({"agent":"revisor","target":"deploy","kind":"x"}),
            ),
            (
                "add_agent",
                json!({"title":"Z","provider_settings":{"foo":{}}}),
            ),
            ("get_agent", json!({})),
            ("import_agents", json!({})),
            ("import_agents", json!({"provider":"codex"})),
            ("add_kit", json!({"items":[]})),
        ],
    );
    assert!(!r[0].0, "{}", r[0].1);
    let a: Value = serde_json::from_str(&r[0].1).unwrap();
    assert_eq!(a["slug"], "revisor");
    assert_eq!(a["providerSettings"]["codex"]["model"], "gpt");
    assert_eq!(a["author"], "ai");
    let s: Value = serde_json::from_str(&r[2].1).unwrap();
    assert_eq!(s["slug"], "qualidade/lint");
    let step: Value = serde_json::from_str(&r[3].1).unwrap();
    assert_eq!(step["nextSteps"][0]["kind"], "command");
    let c: Value = serde_json::from_str(&r[4].1).unwrap();
    assert_eq!(c["tags"], json!(["a", "b"]));
    assert_eq!(c["summary"], "Publica");
    let list: Value = serde_json::from_str(&r[6].1).unwrap();
    assert_eq!(list[0]["slug"], "revisor");
    assert_eq!(list[0]["nextSteps"].as_array().unwrap().len(), 1);
    let skills: Value = serde_json::from_str(&r[7].1).unwrap();
    assert_eq!(skills[0]["group"], "qualidade");
    assert!(r[8].1.contains("deploy"));
    assert_eq!(r[9], (true, "Invalid params: Tipo inválido: x".to_string()));
    assert_eq!(
        r[10],
        (
            true,
            "Invalid params: Provedor inválido em provider_settings".to_string()
        )
    );
    assert_eq!(
        r[11],
        (
            true,
            "Invalid params: Parâmetro obrigatório: agent".to_string()
        )
    );
    assert_eq!(r[12], (false, "[\n\n]".to_string()));
    assert!(!r[13].0);
    let codex: Value = serde_json::from_str(&r[13].1).unwrap();
    assert!(codex["slugs"].is_array() && codex["warnings"].is_array());
    assert!(r[14].0);
}

#[test]
fn mcp_import_claude_le_arquivos_do_projeto() {
    let d = Dir::new();
    let dir = d.0.join(".claude/agents");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("rev.md"),
        "---\nname: rev\ndescription: Revisa\nmodel: opus\n---\nFaça a revisão.\n",
    )
    .unwrap();
    let r = mcp(
        &d.0,
        &[
            ("import_agents", json!({})),
            ("get_agent", json!({"agent":"rev"})),
        ],
    );
    assert_eq!(r[0], (false, "[\n  \"rev\"\n]".to_string()));
    let a: Value = serde_json::from_str(&r[1].1).unwrap();
    assert_eq!(a["prompt"].as_str().unwrap().trim(), "Faça a revisão.");
}
