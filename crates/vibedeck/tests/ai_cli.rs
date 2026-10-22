//! Integração do binário: `vibedeck ai|usage|reorganize ...` e as tools MCP de IA, sobre um projeto
//! temporário. Nenhum teste chama `claude`/`codex` reais: os executáveis são scripts falsos em tempdir,
//! injetados por `VIBEDECK_CLAUDE_BIN` / `VIBEDECK_CODEX_BIN`.

use serde_json::{Value, json};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Once;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Instant;

static N: AtomicU32 = AtomicU32::new(0);
static INIT: Once = Once::new();

fn support_dir() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("vibedeck-ai-support-{}", std::process::id()));
    INIT.call_once(|| {
        std::fs::create_dir_all(&dir).unwrap();
        // SAFETY: executado uma vez, antes de qualquer thread de teste ler a variável.
        unsafe { std::env::set_var("VIBEDECK_APP_SUPPORT", &dir) };
    });
    dir
}

struct Proj {
    root: PathBuf,
    home: PathBuf,
    extra: Vec<(String, String)>,
}

impl Proj {
    fn new() -> Self {
        let support = support_dir();
        let base = std::env::temp_dir().join(format!(
            "vibedeck-ai-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let root = base.join("proj");
        let home = base.join("home");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&home).unwrap();
        vibedeck_core::Store::init(&root, "Projeto", None).unwrap();
        let _ = support;
        Proj {
            root,
            home,
            extra: vec![],
        }
    }

    fn base(&self) -> &Path {
        self.root.parent().unwrap()
    }

    fn env(&mut self, k: &str, v: impl AsRef<str>) -> &mut Self {
        self.extra.push((k.to_string(), v.as_ref().to_string()));
        self
    }

    fn command(&self) -> Command {
        let mut c = Command::new(env!("CARGO_BIN_EXE_vibedeck"));
        c.env("HOME", &self.home)
            .env("VIBEDECK_APP_SUPPORT", support_dir())
            .env("SHELL", "/bin/sh")
            .env_remove("VIBEDECK_CLAUDE_BIN")
            .env_remove("VIBEDECK_CODEX_BIN")
            .env_remove("VIBEDECK_AI_TIMEOUT_SECS");
        for (k, v) in &self.extra {
            c.env(k, v);
        }
        c
    }

    fn cli(&self, args: &[&str]) -> (i32, String, String) {
        self.cli_in(Some(&self.root), args, "")
    }

    fn cli_in(&self, root: Option<&Path>, args: &[&str], stdin: &str) -> (i32, String, String) {
        let mut c = self.command();
        if let Some(r) = root {
            c.arg("-C").arg(r);
        }
        let mut child = c
            .args(args)
            .current_dir(self.base())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        let out = child.wait_with_output().unwrap();
        (
            out.status.code().unwrap(),
            String::from_utf8(out.stdout).unwrap(),
            String::from_utf8(out.stderr).unwrap(),
        )
    }

    fn mcp(&self, calls: &[(&str, Value)]) -> Vec<(bool, String)> {
        let mut input = String::new();
        for (i, (name, args)) in calls.iter().enumerate() {
            input.push_str(
                &json!({"jsonrpc":"2.0","id":i + 1,"method":"tools/call",
                    "params":{"name":name,"arguments":args}})
                .to_string(),
            );
            input.push('\n');
        }
        let mut child = self
            .command()
            .arg("-C")
            .arg(&self.root)
            .arg("mcp")
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

    fn data(&self) -> PathBuf {
        self.root.join(".vibedeck")
    }

    fn script(&self, name: &str, body: &str) -> PathBuf {
        let path = self.base().join(name);
        std::fs::write(&path, body).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    fn doc(&self, slug: &str, text: &str) {
        let path = self.data().join("docs").join(format!("{slug}.md"));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
}

impl Drop for Proj {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.base());
    }
}

fn ok(r: (i32, String, String)) -> String {
    assert_eq!(r.0, 0, "stderr: {}", r.2);
    r.1
}

fn parse(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|e| panic!("{e}: {text}"))
}

fn python3() -> bool {
    Command::new("python3").arg("--version").output().is_ok()
}

// ---- ai guide / catalog / context / usage ----------------------------------------------------------

#[test]
fn guide_indice_secao_e_json() {
    let p = Proj::new();
    let index = ok(p.cli_in(None, &["ai", "guide"], ""));
    assert!(index.starts_with("0: "));
    assert!(!index.to_lowercase().contains("nuvem"));
    let count = index.lines().count();
    let section = ok(p.cli_in(None, &["ai", "guide", "--section", "0"], ""));
    assert!(section.starts_with("## "));
    let as_json = ok(p.cli_in(None, &["ai", "guide", "--section", "0", "--json"], ""));
    assert!(as_json.starts_with("\"## "));
    assert_eq!(
        parse(&as_json).as_str().unwrap(),
        section.strip_suffix('\n').unwrap()
    );
    let missing = p.cli_in(None, &["ai", "guide", "--section", &count.to_string()], "");
    assert_eq!((missing.0, missing.1.as_str()), (1, ""));
    assert_eq!(missing.2, "Error: Seção inexistente.\n");
    let index_json = ok(p.cli_in(None, &["ai", "guide", "--json"], ""));
    assert_eq!(
        parse(&index_json).as_str().unwrap(),
        index.strip_suffix('\n').unwrap()
    );

    let r = p.mcp(&[
        ("ai_guide", json!({})),
        ("ai_guide", json!({"section": 0})),
        ("ai_guide", json!({"section": 9999})),
        ("ai_guide", json!({"section": "0"})),
    ]);
    assert_eq!(r[0], (false, index.strip_suffix('\n').unwrap().to_string()));
    assert_eq!(
        r[1],
        (false, section.strip_suffix('\n').unwrap().to_string())
    );
    assert_eq!(
        r[2],
        (true, "Invalid params: Seção inexistente.".to_string())
    );
    // `.intValue` estrito: texto não vale e cai no índice
    assert_eq!(r[3], r[0]);
}

#[test]
fn catalogo_cli_e_mcp() {
    let p = Proj::new();
    for name in ["A", "B", "C"] {
        let mut agent = vibedeck_core::model::Agent::new(name);
        agent.summary = Some("Uso específico".into());
        agent.prompt = "segredo ".repeat(50);
        vibedeck_core::Store::open(&p.root)
            .unwrap()
            .create(&agent, None)
            .unwrap();
    }
    let text = ok(p.cli(&["ai", "catalog", "agents", "--limit", "2"]));
    assert_eq!(
        text,
        "a: A — Uso específico\nb: B — Uso específico\nContinuação: --offset 2\n"
    );
    let json = parse(&ok(p.cli(&[
        "ai", "catalog", "agents", "--json", "--offset", "2", "--limit", "2",
    ])));
    assert_eq!(json["total"], 3);
    assert!(json.get("nextOffset").is_none());
    assert!(!json.to_string().contains("segredo"));
    let bad = p.cli(&["ai", "catalog", "x"]);
    assert_eq!(bad.0, 1);
    assert!(
        bad.2
            .contains("Catálogo inválido: use agents, commands, skills, workflows ou rules.")
    );
    assert_eq!(p.cli(&["ai", "catalog", "agents", "--limit", "0"]).0, 1);

    let r = p.mcp(&[
        ("ai_catalog", json!({"kind": "agents", "limit": 1})),
        ("ai_catalog", json!({"kind": "rules"})),
        ("ai_catalog", json!({"kind": "agents", "limit": 0})),
        ("ai_catalog", json!({})),
    ]);
    assert!(!r[0].0);
    assert_eq!(parse(&r[0].1)["nextOffset"], 1);
    assert_eq!(parse(&r[1].1)["total"], 0);
    assert_eq!(
        r[2],
        (
            true,
            "Referência ou intervalo inválido. Use offset ≥ 0 e limit entre 1 e 16000.".to_string()
        )
    );
    assert_eq!(
        r[3],
        (
            true,
            "Invalid params: Parâmetro obrigatório: kind".to_string()
        )
    );
}

#[test]
fn contexto_pagina_sem_perder_o_resto() {
    let p = Proj::new();
    let store = vibedeck_core::ai::context::ContextStore::for_root(&p.root);
    let text = "linha de decisão\n".repeat(30);
    let reference = store.save(&text, "Decisões").unwrap();
    let page = parse(&ok(p.cli(&[
        "ai",
        "context",
        &reference.id,
        "--limit",
        "100",
        "--json",
    ])));
    assert_eq!(page["nextOffset"], 100);
    assert_eq!(page["totalCharacters"], text.chars().count());
    let plain = ok(p.cli(&["ai", "context", &reference.id, "--limit", "100"]));
    assert!(plain.ends_with(&format!(
        "\nContinuação: --offset 100 (total: {} caracteres)\n",
        text.chars().count()
    )));
    let last = ok(p.cli(&["ai", "context", &reference.id, "--offset", "400"]));
    assert_eq!(
        last,
        format!("{}\n", text.chars().skip(400).collect::<String>())
    );
    assert_eq!(p.cli(&["ai", "context", "../../secret"]).0, 1);
    assert_eq!(
        p.cli(&["ai", "context", &reference.id, "--limit", "16001"])
            .0,
        1
    );
    let r = p.mcp(&[
        ("ai_context", json!({"id": reference.id, "limit": 50})),
        ("ai_context", json!({"id": reference.id, "offset": -1})),
    ]);
    assert_eq!(
        parse(&r[0].1)["text"].as_str().unwrap(),
        text.chars().take(50).collect::<String>()
    );
    assert!(r[1].0);
}

#[test]
fn uso_local_lista_e_limpa() {
    let p = Proj::new();
    let store = vibedeck_core::ai::usage::UsageStore::for_root(&p.root);
    let mut record = vibedeck_core::ai::usage::UsageRecord::new(
        "Teste",
        vibedeck_core::ai::Provider::Codex,
        "segredo",
    );
    record.tokens.input = Some(200);
    record.finish("completed");
    store.save(&record).unwrap();
    let text = ok(p.cli(&["ai", "usage"]));
    assert_eq!(
        text,
        format!(
            "Teste · Codex · modelo não informado · tarefa {} · tentativa 1 · entrada 200 · saída não informada · completed\n",
            record.task_id
        )
    );
    let json = parse(&ok(p.cli(&["ai", "usage", "--json"])));
    assert_eq!(json[0]["tokens"]["input"], 200);
    assert!(!json.to_string().contains("segredo"));
    let mcp = p.mcp(&[("ai_usage", json!({}))]);
    assert_eq!(parse(&mcp[0].1), json);
    assert_eq!(ok(p.cli(&["ai", "usage", "--clear"])), "");
    assert_eq!(ok(p.cli(&["ai", "usage", "--json"])), "[\n\n]\n");
    store.save(&record).unwrap();
    let r = p.mcp(&[
        ("ai_usage", json!({"clear": true})),
        ("ai_usage", json!({"clear": "true"})),
    ]);
    assert_eq!(r[0], (false, "Métricas locais apagadas.".to_string()));
    assert_eq!(r[1], (false, "[\n\n]".to_string()));
}

// ---- item-prompt / item-apply -----------------------------------------------------------------------

#[test]
fn item_prompt_e_apply_pelo_cli_e_mcp() {
    let p = Proj::new();
    let out = parse(&ok(p.cli(&[
        "ai",
        "item-prompt",
        "agent",
        "--request",
        "Crie um revisor",
    ])));
    assert!(
        out["prompt"]
            .as_str()
            .unwrap()
            .contains("Crie um agente do VibeDeck")
    );
    assert!(out["schema"].as_str().unwrap().contains("\"prompt\""));
    let bad = p.cli(&["ai", "item-prompt", "robot", "--request", "x"]);
    assert_eq!(
        (bad.0, bad.2.as_str()),
        (
            1,
            "Error: Tipo inválido: use agent, command, skill ou workflow.\n"
        )
    );
    let blank = p.cli(&["ai", "item-prompt", "agent", "--request", "  "]);
    assert!(blank.2.ends_with("Descreva o que a IA deve fazer.\n"));

    let proposal =
        r#"{"title":"Revisor","summary":"Revisa","prompt":"Você revisa PRs.","tags":["a"]}"#;
    let file = p.base().join("proposta.json");
    std::fs::write(&file, proposal).unwrap();
    assert_eq!(
        ok(p.cli(&[
            "ai",
            "item-apply",
            "agent",
            "--file",
            file.to_str().unwrap()
        ])),
        "revisor\n"
    );
    assert_eq!(
        ok(p.cli_in(
            Some(&p.root),
            &["ai", "item-apply", "agent", "--file", "-"],
            proposal
        )),
        "revisor-2\n"
    );
    let edit = r#"{"title":"Revisor","prompt":"novo texto"}"#;
    assert_eq!(
        ok(p.cli_in(
            Some(&p.root),
            &[
                "ai",
                "item-apply",
                "agent",
                "--file",
                "-",
                "--item",
                "revisor"
            ],
            edit
        )),
        "revisor\n"
    );
    let saved = parse(&std::fs::read_to_string(p.data().join("agents/revisor.json")).unwrap());
    assert_eq!(saved["prompt"], "novo texto");
    assert_eq!(saved["author"], "ai");
    let invalid = p.cli_in(
        Some(&p.root),
        &["ai", "item-apply", "skill", "--file", "-"],
        "{",
    );
    assert_eq!(invalid.0, 1);
    assert!(invalid.2.contains("JSON válido para skill"));

    let r = p.mcp(&[
        ("item_ai_prompt", json!({"kind": "command", "request": "Crie /deploy", "item": null})),
        ("item_ai_apply", json!({"kind": "command", "proposal": r#"{"title":"Deploy","argumentHint":"<env>","prompt":"Faça deploy $ARGUMENTS"}"#})),
        ("item_ai_apply", json!({"kind": "bad", "proposal": "{}"})),
        ("item_ai_prompt", json!({"kind": "agent"})),
    ]);
    assert!(
        parse(&r[0].1)["prompt"]
            .as_str()
            .unwrap()
            .contains("comando")
    );
    assert_eq!(r[1], (false, "Gravado: deploy".to_string()));
    assert_eq!(
        r[2],
        (
            true,
            "Invalid params: Tipo inválido: use agent, command, skill ou workflow.".to_string()
        )
    );
    assert_eq!(
        r[3],
        (
            true,
            "Invalid params: Parâmetro obrigatório: request".to_string()
        )
    );
    let cmd = parse(&std::fs::read_to_string(p.data().join("commands/deploy.json")).unwrap());
    assert_eq!(cmd["argumentHint"], "<env>");
}

// ---- reorganize ---------------------------------------------------------------------------------------

fn answer_moving(doc: &str) -> Value {
    json!({"actions": [{
        "id": "a1", "kind": "move", "item": {"concept": "docs", "slug": doc, "itemID": null},
        "involved": [], "reason": "Agrupar", "destination": "grupo", "title": null, "content": null
    }]})
}

#[test]
fn reorganize_prompt_validate_apply_pelo_cli() {
    let p = Proj::new();
    p.doc("guia", "# Guia\n\n[Outro](outro.md)\n");
    p.doc("outro", "# Outro\n\n[Guia](guia.md)\n");
    let prompted = parse(&ok(p.cli(&["reorganize", "prompt"])));
    let fp = prompted["fingerprint"].as_str().unwrap().to_string();
    assert_eq!(fp.len(), 64);
    assert!(
        prompted["prompt"]
            .as_str()
            .unwrap()
            .contains("\"slug\" : \"guia\"")
    );
    assert!(parsed_schema(&prompted));

    let answer = p.base().join("resposta.json");
    std::fs::write(&answer, answer_moving("guia").to_string()).unwrap();
    let proposal = parse(&ok(p.cli(&[
        "reorganize",
        "validate",
        "--file",
        answer.to_str().unwrap(),
        "--fingerprint",
        &fp,
    ])));
    assert_eq!(proposal["discarded"], 0);
    assert_eq!(proposal["actions"][0]["id"], "a1");
    // fingerprint errado = projeto mudou
    let stale = p.cli(&[
        "reorganize",
        "validate",
        "--file",
        answer.to_str().unwrap(),
        "--fingerprint",
        "x",
    ]);
    assert_eq!(
        stale.2,
        "Error: O projeto mudou. Analise novamente antes de aceitar a reorganização.\n"
    );
    // entrada pela stdin
    let from_stdin = p.cli_in(
        Some(&p.root),
        &[
            "reorganize",
            "validate",
            "--file",
            "-",
            "--fingerprint",
            &fp,
        ],
        &answer_moving("guia").to_string(),
    );
    assert_eq!(from_stdin.0, 0);
    let invalid = p.cli_in(
        Some(&p.root),
        &[
            "reorganize",
            "validate",
            "--file",
            "-",
            "--fingerprint",
            &fp,
        ],
        "não é json",
    );
    assert!(invalid.2.contains("proposta de reorganização inválida"));
    assert!(p.data().join("docs/guia.md").exists());

    let prop_file = p.base().join("proposta.json");
    std::fs::write(&prop_file, proposal.to_string()).unwrap();
    let acc_file = p.base().join("aceite.json");
    std::fs::write(
        &acc_file,
        json!({"selected": ["a1"], "conflicts": {}}).to_string(),
    )
    .unwrap();
    let receipt = parse(&ok(p.cli(&[
        "reorganize",
        "apply",
        "--file",
        prop_file.to_str().unwrap(),
        "--acceptance",
        acc_file.to_str().unwrap(),
    ])));
    assert!(receipt["after"][".vibedeck/docs/grupo/guia.md"].is_string());
    assert_eq!(
        receipt["pathMoves"][".vibedeck/docs/guia.md"],
        ".vibedeck/docs/grupo/guia.md"
    );
    assert!(!p.data().join("docs/guia.md").exists());
    assert!(p.data().join("docs/grupo/guia.md").exists());
    let outro = std::fs::read_to_string(p.data().join("docs/outro.md")).unwrap();
    assert!(outro.contains("[Guia](grupo/guia.md)"), "{outro}");
    // aplicar de novo: o projeto mudou
    let again = p.cli(&[
        "reorganize",
        "apply",
        "--file",
        prop_file.to_str().unwrap(),
        "--acceptance",
        acc_file.to_str().unwrap(),
    ]);
    assert_eq!(again.0, 1);
    assert!(again.2.contains("O projeto mudou"));
    // `-` não vale em apply: é um caminho
    assert_eq!(
        p.cli(&[
            "reorganize",
            "apply",
            "--file",
            "-",
            "--acceptance",
            acc_file.to_str().unwrap()
        ])
        .0,
        1
    );
}

fn parsed_schema(prompted: &Value) -> bool {
    let schema: Value = serde_json::from_str(prompted["schema"].as_str().unwrap()).unwrap();
    schema["properties"]["actions"]["maxItems"] == 100
}

#[test]
fn reorganize_pelo_mcp() {
    let p = Proj::new();
    p.doc("guia", "# Guia\n");
    let first = p.mcp(&[("reorganize_prompt", json!({}))]);
    let prompted = parse(&first[0].1);
    let fp = prompted["fingerprint"].as_str().unwrap();
    let r = p.mcp(&[
        (
            "reorganize_validate",
            json!({"answer": answer_moving("guia").to_string(), "fingerprint": fp}),
        ),
        (
            "reorganize_validate",
            json!({"answer": "{}", "fingerprint": fp}),
        ),
        ("reorganize_validate", json!({"answer": "{}"})),
        ("reorganize_analyze", json!({})),
        ("reorganize_analyze", json!({"provider": "gemini"})),
        (
            "reorganize_apply",
            json!({"proposal": "x", "acceptance": "{}"}),
        ),
    ]);
    let proposal = parse(&r[0].1);
    assert_eq!(proposal["actions"][0]["destination"], "grupo");
    assert_eq!(
        r[1],
        (
            true,
            "A IA retornou uma proposta de reorganização inválida. Nenhum arquivo foi alterado."
                .to_string()
        )
    );
    assert_eq!(
        r[2],
        (
            true,
            "Invalid params: Parâmetro obrigatório: fingerprint".to_string()
        )
    );
    assert_eq!(
        r[3],
        (
            true,
            "Invalid params: Parâmetro obrigatório: provider".to_string()
        )
    );
    assert_eq!(
        r[4],
        (
            true,
            "Invalid params: Provedor inválido: gemini".to_string()
        )
    );
    assert!(r[5].0);
    let applied = p.mcp(&[(
        "reorganize_apply",
        json!({"proposal": proposal.to_string(), "acceptance": json!({"selected": ["a1"], "conflicts": {}}).to_string()}),
    )]);
    assert!(!applied[0].0, "{}", applied[0].1);
    assert!(p.data().join("docs/grupo/guia.md").exists());
}

const FAKE_CLAUDE: &str = r#"#!/bin/sh
printf '%s\n' "$@" > "$FAKE_ARGS"
pwd > "$FAKE_CWD"
cat > "$FAKE_STDIN"
if [ -n "$FAKE_SLEEP" ]; then sleep "$FAKE_SLEEP"; fi
cat "$FAKE_OUT"
"#;

#[test]
fn reorganize_analyze_com_claude_falso() {
    let mut p = Proj::new();
    p.doc("guia", "# Guia\n");
    let claude = p.script("claude", FAKE_CLAUDE);
    let out = p.base().join("out.json");
    let args = p.base().join("args.txt");
    let stdin = p.base().join("stdin.txt");
    let cwd = p.base().join("cwd.txt");
    p.env("VIBEDECK_CLAUDE_BIN", claude.to_str().unwrap())
        .env("FAKE_OUT", out.to_str().unwrap())
        .env("FAKE_ARGS", args.to_str().unwrap())
        .env("FAKE_STDIN", stdin.to_str().unwrap())
        .env("FAKE_CWD", cwd.to_str().unwrap());

    let envelope = json!({"type": "result", "subtype": "success", "is_error": false,
        "structured_output": answer_moving("guia")});
    std::fs::write(&out, format!("{}\n", envelope)).unwrap();
    let proposal = parse(&ok(p.cli(&[
        "reorganize",
        "analyze",
        "--provider",
        "claude",
        "--model",
        "sonnet",
        "--effort",
        "high",
    ])));
    assert_eq!(proposal["actions"][0]["id"], "a1");
    assert_eq!(proposal["discarded"], 0);
    let argv = std::fs::read_to_string(&args).unwrap();
    let argv: Vec<&str> = argv.lines().collect();
    assert_eq!(argv[0], "-p");
    assert!(argv.windows(2).any(|w| w == ["--tools", "Read,Grep,Glob"]));
    assert!(
        argv.windows(2)
            .any(|w| w == ["--allowedTools", "Read,Grep,Glob"])
    );
    assert!(argv.contains(&"--strict-mcp-config") && argv.contains(&"--no-session-persistence"));
    assert!(argv.windows(2).any(|w| w == ["--model", "sonnet"]));
    assert!(argv.windows(2).any(|w| w == ["--effort", "high"]));
    assert!(
        argv.windows(2)
            .any(|w| w[0] == "--json-schema" && w[1].contains("\"actions\""))
    );
    assert!(
        std::fs::read_to_string(&stdin)
            .unwrap()
            .contains("Analise a organização deste projeto")
    );
    assert_eq!(
        std::fs::canonicalize(std::fs::read_to_string(&cwd).unwrap().trim()).unwrap(),
        std::fs::canonicalize(&p.root).unwrap()
    );
    // nada foi gravado em `.vibedeck`
    assert!(p.data().join("docs/guia.md").exists());

    // sem structured_output: usa `result` como texto
    let text_envelope = json!({"type": "result", "subtype": "success", "result": answer_moving("guia").to_string()});
    std::fs::write(&out, format!("log antes\n{}\n", text_envelope)).unwrap();
    let via_text = ok(p.cli(&["reorganize", "analyze", "--provider", "claude"]));
    assert_eq!(parse(&via_text)["actions"][0]["id"], "a1");

    // via MCP
    let mcp = p.mcp(&[(
        "reorganize_analyze",
        json!({"provider": "claude", "model": "opus"}),
    )]);
    assert!(!mcp[0].0, "{}", mcp[0].1);
    assert_eq!(parse(&mcp[0].1)["actions"].as_array().unwrap().len(), 1);

    // erro do provider
    std::fs::write(
        &out,
        json!({"type": "result", "subtype": "error_max_turns", "is_error": true}).to_string(),
    )
    .unwrap();
    let failed = p.cli(&["reorganize", "analyze", "--provider", "claude"]);
    assert_eq!(failed.0, 1);
    assert!(failed.2.contains("proposta de reorganização inválida"));
    std::fs::write(&out, "lixo").unwrap();
    assert_eq!(
        p.cli(&["reorganize", "analyze", "--provider", "claude"]).0,
        1
    );

    // provider inválido
    let invalid = p.cli(&["reorganize", "analyze", "--provider", "gemini"]);
    assert_eq!(
        (invalid.0, invalid.2.as_str()),
        (1, "Error: Use claude ou codex.\n")
    );
}

#[test]
fn reorganize_analyze_sem_claude_e_com_prazo() {
    let mut p = Proj::new();
    p.doc("guia", "# Guia\n");
    p.env(
        "VIBEDECK_CLAUDE_BIN",
        p.base().join("nao-existe").to_str().unwrap(),
    );
    let missing = p.cli(&["reorganize", "analyze", "--provider", "claude"]);
    assert_eq!(
        (missing.0, missing.2.as_str()),
        (1, "Error: Claude não está instalado.\n")
    );

    let claude = p.script("claude", FAKE_CLAUDE);
    let out = p.base().join("out.json");
    std::fs::write(&out, "{}").unwrap();
    for (k, v) in [
        ("VIBEDECK_CLAUDE_BIN", claude.to_str().unwrap().to_string()),
        ("FAKE_OUT", out.to_str().unwrap().into()),
        ("FAKE_ARGS", p.base().join("a").to_str().unwrap().into()),
        ("FAKE_STDIN", p.base().join("s").to_str().unwrap().into()),
        ("FAKE_CWD", p.base().join("c").to_str().unwrap().into()),
        ("FAKE_SLEEP", "5".into()),
        ("VIBEDECK_AI_TIMEOUT_SECS", "0.4".into()),
    ] {
        p.env(k, v);
    }
    let started = Instant::now();
    let slow = p.cli(&["reorganize", "analyze", "--provider", "claude"]);
    assert!(
        started.elapsed().as_secs() < 4,
        "o prazo não matou o processo"
    );
    assert_eq!(slow.0, 1);
    assert_eq!(
        slow.2,
        "Error: O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo.\n"
    );
}

const FAKE_CODEX: &str = r#"
import json, os, sys
def emit(v):
    print(json.dumps(v), flush=True)
rec = {"requests": []}
def save():
    open(os.environ["FAKE_REC"], "w").write(json.dumps(rec))
mode = os.environ.get("FAKE_MODE", "analyze")
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get("method"); mid = msg.get("id")
    if method:
        rec["requests"].append({"method": method, "params": msg.get("params")})
        save()
    if method == "initialize": emit({"id": mid, "result": {}})
    elif method == "config/read": emit({"id": mid, "result": {"config": {"mcp_servers": {"externo": {"enabled": True}}}}})
    elif method == "thread/start": emit({"id": mid, "result": {"thread": {"id": "t1"}, "model": "gpt-test"}})
    elif method == "model/list": emit({"id": mid, "result": {"data": [{"model": "gpt-test", "supportedReasoningEfforts": [{"reasoningEffort": "high"}]}]}})
    elif method == "account/rateLimits/read":
        emit({"id": mid, "result": {"rateLimits": {"primary": {"usedPercent": 30.5, "windowDurationMins": 300, "resetsAt": 1000}, "secondary": {"usedPercent": 10, "windowDurationMins": 10080}}}})
    elif method == "skills/list":
        emit({"id": mid, "result": {"data": [{"errors": [{"path": "/x/bad", "message": "quebrada"}], "skills": [
            {"name": "u", "path": os.environ["FAKE_SKILL_USER"], "enabled": True},
            {"name": "p", "path": os.environ["FAKE_SKILL_PROJECT"]},
            {"name": "d", "path": "/off/SKILL.md", "enabled": False}]}]}})
    elif method == "turn/start":
        emit({"id": mid, "result": {"turn": {"id": "u1"}}})
        emit({"id": "call1", "method": "item/tool/call", "params": {"threadId": "t1", "tool": "Read", "arguments": {"path": "vibedeck.json", "limit": 1}}})
        emit({"id": "call2", "method": "item/tool/call", "params": {"threadId": "t1", "tool": "Bash", "arguments": {}}})
        emit({"id": "ask", "method": "item/commandExecution/requestApproval", "params": {"threadId": "t1"}})
    elif mid in ("call1", "call2", "ask") and "result" in msg:
        rec[mid] = msg["result"]; save()
        if mid == "ask":
            text = open(os.environ["FAKE_ANSWER"]).read()
            emit({"method": "thread/tokenUsage/updated", "params": {"threadId": "t1", "tokenUsage": {"total": {"inputTokens": 5, "outputTokens": 2}}}})
            emit({"method": "item/completed", "params": {"threadId": "t1", "item": {"id": "m1", "type": "agentMessage", "phase": "final_answer", "text": text}}})
            emit({"method": "turn/completed", "params": {"threadId": "t1", "turn": {"id": "u1", "status": "completed"}}})
"#;

#[test]
fn reorganize_analyze_e_limites_com_codex_falso() {
    if !python3() {
        return;
    }
    let mut p = Proj::new();
    p.doc("guia", "# Guia\n");
    let codex = p.script(
        "codex",
        &format!("#!/bin/sh\nexec python3 -u \"{}\" \"$@\"\n", {
            let py = p.base().join("fake_codex.py");
            std::fs::write(&py, FAKE_CODEX).unwrap();
            py.display().to_string()
        }),
    );
    let rec = p.base().join("rec.json");
    let answer = p.base().join("answer.txt");
    std::fs::write(&answer, answer_moving("guia").to_string()).unwrap();
    let skill_user = p.base().join("user-skills/u/SKILL.md");
    let skill_project = p.root.join("skills/p/SKILL.md");
    p.env("VIBEDECK_CODEX_BIN", codex.to_str().unwrap())
        .env("FAKE_REC", rec.to_str().unwrap())
        .env("FAKE_ANSWER", answer.to_str().unwrap())
        .env("FAKE_SKILL_USER", skill_user.to_str().unwrap())
        .env("FAKE_SKILL_PROJECT", skill_project.to_str().unwrap());

    let proposal = parse(&ok(p.cli(&[
        "reorganize",
        "analyze",
        "--provider",
        "codex",
        "--model",
        "gpt-test",
        "--effort",
        "high",
    ])));
    assert_eq!(proposal["actions"][0]["id"], "a1");
    let recorded = parse(&std::fs::read_to_string(&rec).unwrap());
    let call = |method: &str| {
        recorded["requests"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["method"] == method)
            .unwrap()["params"]
            .clone()
    };
    let thread = call("thread/start");
    assert_eq!(thread["sandbox"], "read-only");
    assert_eq!(thread["approvalPolicy"], "never");
    assert_eq!(thread["ephemeral"], true);
    assert_eq!(thread["model"], "gpt-test");
    assert_eq!(thread["allowProviderModelFallback"], false);
    assert_eq!(thread["config"]["features.shell_tool"], false);
    assert_eq!(thread["config"]["features.unified_exec"], false);
    assert_eq!(thread["config"]["mcp_servers.externo.enabled"], false);
    let tools: Vec<&str> = thread["dynamicTools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap())
        .collect();
    assert_eq!(tools, ["Read", "Glob", "Grep"]);
    assert!(
        thread["developerInstructions"]
            .as_str()
            .unwrap()
            .starts_with("Antes de implementar")
    );
    let turn = call("turn/start");
    assert_eq!(turn["effort"], "high");
    assert_eq!(turn["outputSchema"]["additionalProperties"], false);
    assert!(
        turn["input"][0]["text"]
            .as_str()
            .unwrap()
            .contains("Analise a organização")
    );
    // ferramenta de leitura atendida; Bash recusado; aprovação negada
    assert_eq!(recorded["call1"]["success"], true);
    assert!(
        recorded["call1"]["contentItems"][0]["text"]
            .as_str()
            .unwrap()
            .starts_with("vibedeck.json:1:")
    );
    assert_eq!(recorded["call2"]["success"], false);
    assert_eq!(recorded["ask"]["decision"], "decline");

    // modelo indisponível
    let bad_model = p.cli(&[
        "reorganize",
        "analyze",
        "--provider",
        "codex",
        "--model",
        "outro",
    ]);
    // o app-server devolve `gpt-test` mesmo assim; o modelo pedido não existe na lista? existe: aceita.
    assert_eq!(bad_model.0, 0, "{}", bad_model.2);
    let bad_effort = p.cli(&[
        "reorganize",
        "analyze",
        "--provider",
        "codex",
        "--effort",
        "xhigh",
    ]);
    assert_eq!(
        bad_effort.2,
        "Error: Esforço xhigh indisponível para gpt-test. Escolha outro esforço explicitamente.\n"
    );

    // limites
    let text = ok(p.cli_in(None, &["usage", "--provider", "codex"], ""));
    assert_eq!(
        text,
        "codex · primary: 30% · 300 min\ncodex · secondary: 10% · 10080 min\n"
    );
    let json = parse(&ok(p.cli_in(
        None,
        &["usage", "show", "--provider", "codex", "--json"],
        "",
    )));
    assert_eq!(json["rateLimits"]["primary"]["usedPercent"], 30.5);
    let mcp = p.mcp(&[("codex_usage", json!({}))]);
    assert_eq!(parse(&mcp[0].1), json);

    // skills do Codex (parte com provider do import_skills)
    std::fs::create_dir_all(skill_project.parent().unwrap()).unwrap();
    let (paths, warnings) = vibedeck_core::ai::codex::skill_paths_with(
        &p.root,
        std::path::Path::new(codex.to_str().unwrap()),
        &[
            ("FAKE_REC", rec.to_str().unwrap()),
            ("FAKE_SKILL_USER", skill_user.to_str().unwrap()),
            ("FAKE_SKILL_PROJECT", skill_project.to_str().unwrap()),
        ],
    )
    .unwrap();
    assert_eq!(paths, vec![skill_project, skill_user]);
    assert_eq!(warnings, vec!["/x/bad: quebrada".to_string()]);
}

#[test]
fn codex_ausente_e_erro_do_app_server() {
    let mut p = Proj::new();
    p.doc("guia", "# Guia\n");
    p.env(
        "VIBEDECK_CODEX_BIN",
        p.base().join("nao-existe").to_str().unwrap(),
    );
    let r = p.cli(&["reorganize", "analyze", "--provider", "codex"]);
    assert_eq!(
        r.2,
        "Error: Codex não encontrado. Instale o Codex CLI e reabra o VibeDeck.\n"
    );
    let usage = p.cli_in(None, &["usage", "--provider", "codex"], "");
    assert_eq!(usage.0, 1);
    let mcp = p.mcp(&[("codex_usage", json!({}))]);
    assert_eq!(
        mcp[0],
        (
            true,
            "Codex não encontrado. Instale o Codex CLI e reabra o VibeDeck.".to_string()
        )
    );
    // processo que morre antes do handshake
    let dead = p.script("codex", "#!/bin/sh\necho 'falhou ao iniciar' >&2\nexit 3\n");
    p.extra.retain(|(k, _)| k != "VIBEDECK_CODEX_BIN");
    p.env("VIBEDECK_CODEX_BIN", dead.to_str().unwrap());
    let r = p.cli(&["reorganize", "analyze", "--provider", "codex"]);
    assert_eq!(r.0, 1);
    assert!(r.2.contains("Codex: falhou ao iniciar"), "{}", r.2);
}

// ---- usage (statusline do Claude Code) -----------------------------------------------------------------

#[test]
fn usage_record_show_install_uninstall() {
    let p = Proj::new();
    // nenhum uso ainda
    let none = p.cli_in(None, &["usage"], "");
    assert_eq!(
        (none.0, none.2.as_str()),
        (
            1,
            "Error: Nenhum uso registrado ainda. Rode `vibedeck usage install` e use o Claude Code.\n"
        )
    );
    let mcp = p.mcp(&[("claude_usage", json!({}))]);
    assert_eq!(mcp[0], (false, "Nenhum uso registrado. O usuário precisa ligar a statusline com `vibedeck usage install`.".to_string()));

    let status = r#"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":4102444800},"seven_day":{"used_percentage":18,"resets_at":4102444800}}}"#;
    let recorded = ok(p.cli_in(None, &["usage", "record"], status));
    assert!(
        recorded.starts_with("Opus · sessão 42% (reinicia "),
        "{recorded}"
    );
    assert!(recorded.trim_end().ends_with(") · semana 18%"));
    let shown = ok(p.cli_in(None, &["usage"], ""));
    assert!(shown.starts_with("Opus · sessão 42%"));
    assert!(shown.contains("\nAtualizado em "));
    let json = parse(&ok(p.cli_in(None, &["usage", "show", "--json"], "")));
    assert_eq!(json["weekly"]["usedPercentage"], 18);
    assert_eq!(json["session"]["usedPercentage"], 42.4);
    assert_eq!(json["model"], "Opus");
    assert_eq!(parse(&p.mcp(&[("claude_usage", json!({}))])[0].1), json);

    // sem limites mantém o último valor; JSON inválido não falha
    assert_eq!(
        ok(p.cli_in(
            None,
            &["usage", "record"],
            r#"{"model":{"display_name":"Sonnet"}}"#
        )),
        "Sonnet\n"
    );
    assert_eq!(ok(p.cli_in(None, &["usage", "record"], "lixo")), "");
    assert_eq!(
        parse(&ok(p.cli_in(None, &["usage", "--json"], "")))["model"],
        "Opus"
    );

    // --then recebe o mesmo JSON e a saída dele é a que aparece
    let then = ok(p.cli_in(
        None,
        &["usage", "record", "--then", "cat | tr a-z A-Z"],
        r#"{"x":"abc"}"#,
    ));
    assert_eq!(then, "{\"X\":\"ABC\"}");

    // install/uninstall encadeiam e restauram a statusline existente
    let settings = p.home.join(".claude/settings.json");
    std::fs::create_dir_all(settings.parent().unwrap()).unwrap();
    std::fs::write(
        &settings,
        r#"{"model":"opus","statusLine":{"type":"command","command":"echo oi"}}"#,
    )
    .unwrap();
    let installed = ok(p.cli_in(None, &["usage", "install"], ""));
    assert_eq!(
        installed,
        format!(
            "Statusline ligada em {}. O uso aparece depois da próxima resposta do Claude Code.\n",
            settings.display()
        )
    );
    let value = parse(&std::fs::read_to_string(&settings).unwrap());
    let command = value["statusLine"]["command"].as_str().unwrap();
    assert!(
        command.contains("usage record --then 'echo oi'"),
        "{command}"
    );
    assert_eq!(value["model"], "opus");
    ok(p.cli_in(None, &["usage", "install"], ""));
    assert_eq!(parse(&std::fs::read_to_string(&settings).unwrap()), value);
    let removed = ok(p.cli_in(None, &["usage", "uninstall"], ""));
    assert_eq!(
        removed,
        format!(
            "Statusline do VibeDeck removida de {}.\n",
            settings.display()
        )
    );
    assert_eq!(
        parse(&std::fs::read_to_string(&settings).unwrap())["statusLine"]["command"],
        "echo oi"
    );
    std::fs::write(&settings, "[1]").unwrap();
    let bad = p.cli_in(None, &["usage", "install"], "");
    assert_eq!(bad.0, 1);
    assert!(
        bad.2
            .contains("não é um objeto JSON válido; corrija antes de ligar a statusline.")
    );
}

// ---- contrato das tools ---------------------------------------------------------------------------------

#[test]
fn tools_de_ia_no_tools_list() {
    let p = Proj::new();
    let mut child = p
        .command()
        .arg("-C")
        .arg(&p.root)
        .arg("mcp")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}\n")
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let v: Value = serde_json::from_slice(&out.stdout).unwrap();
    let tools = v["result"]["tools"].as_array().unwrap();
    let find = |name: &str| {
        tools
            .iter()
            .find(|t| t["name"] == name)
            .unwrap_or_else(|| panic!("{name}"))
            .clone()
    };
    for (name, read_only) in [
        ("ai_guide", true),
        ("ai_catalog", true),
        ("ai_context", true),
        ("ai_usage", false),
        ("claude_usage", true),
        ("codex_usage", true),
        ("reorganize_prompt", true),
        ("reorganize_analyze", true),
        ("reorganize_validate", true),
        ("reorganize_apply", false),
        ("item_ai_prompt", true),
        ("item_ai_apply", false),
    ] {
        let t = find(name);
        assert_eq!(
            t["annotations"]["readOnlyHint"] == true,
            read_only,
            "{name}"
        );
        assert!(t["description"].is_string(), "{name}");
    }
    assert_eq!(
        find("ai_guide")["inputSchema"],
        json!({"type": "object", "properties": {"section": {"type": "integer"}}})
    );
    assert_eq!(
        find("ai_catalog")["inputSchema"]["required"],
        json!(["kind"])
    );
    assert_eq!(
        find("ai_catalog")["inputSchema"]["properties"]["limit"]["type"],
        "integer"
    );
    assert_eq!(
        find("ai_usage")["inputSchema"]["properties"]["clear"]["type"],
        "boolean"
    );
    assert_eq!(
        find("reorganize_analyze")["inputSchema"]["required"],
        json!(["provider"])
    );
    assert_eq!(
        find("item_ai_apply")["inputSchema"]["required"],
        json!(["kind", "proposal"])
    );
    assert_eq!(
        find("reorganize_prompt")["inputSchema"],
        json!({"type": "object"})
    );
}
