//! Integração do binário: `vibedeck ideas ...` e as tools MCP de ideias, sobre um projeto temporário.

use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};

static N: AtomicU32 = AtomicU32::new(0);

struct Proj(PathBuf);

impl Proj {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "vibedeck-ideas-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&p).unwrap();
        std::fs::write(p.join("vibedeck.json"), "{}").unwrap();
        Proj(p)
    }
    fn path(&self) -> &Path {
        &self.0
    }
    fn cli(&self, args: &[&str]) -> (i32, String, String) {
        let out = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
            .arg("-C")
            .arg(&self.0)
            .args(args)
            .output()
            .unwrap();
        (
            out.status.code().unwrap(),
            String::from_utf8(out.stdout).unwrap(),
            String::from_utf8(out.stderr).unwrap(),
        )
    }
    /// Roda uma sequência de `tools/call`; devolve `(isError, text)` de cada uma.
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
        let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
            .arg("-C")
            .arg(&self.0)
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
}

impl Drop for Proj {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn ok(r: (i32, String, String)) -> String {
    assert_eq!(r.0, 0, "stderr: {}", r.2);
    r.1
}

#[test]
fn cli_crud_list_show_and_json() {
    let p = Proj::new();
    assert_eq!(ok(p.cli(&["ideas"])), "");
    assert_eq!(ok(p.cli(&["ideas", "list", "--json"])), "[\n\n]\n");
    assert_eq!(
        ok(p.cli(&[
            "ideas",
            "new",
            "Minha ideia",
            "--body",
            "texto",
            "--tags",
            "a",
            "b"
        ])),
        "minha-ideia\n"
    );
    assert_eq!(
        ok(p.cli(&[
            "ideas",
            "new",
            "Outra",
            "--reference",
            "grupo/sub/outra",
            "--ai"
        ])),
        "grupo/sub/outra\n"
    );
    let list = ok(p.cli(&["ideas"]));
    // ordem (createdAt, slug): sem fração de segundo o empate cai no slug
    let mut lines: Vec<&str> = list.lines().collect();
    lines.sort();
    assert_eq!(
        lines,
        [
            "grupo/sub/outra\t[new] Outra  (0 regra(s))",
            "minha-ideia\t[new] Minha ideia  (0 regra(s))  #a #b"
        ]
    );
    // o comando padrão aceita as opções de list
    assert_eq!(ok(p.cli(&["ideas", "--status", "done"])), "");
    assert_eq!(
        ok(p.cli(&[
            "ideas",
            "set",
            "minha-ideia",
            "--status",
            "exploring",
            "--title",
            "Nova"
        ])),
        "minha-ideia\t[exploring] Nova\n"
    );
    let rows: Value = serde_json::from_str(&ok(p.cli(&[
        "ideas",
        "list",
        "--json",
        "--status",
        "exploring",
    ])))
    .unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 1);
    assert_eq!(rows[0]["slug"], "minha-ideia");
    assert_eq!(rows[0]["group"], "");
    assert_eq!(rows[0]["title"], "Nova");
    let nested: Value = serde_json::from_str(&ok(p.cli(&["ideas", "list", "--json"]))).unwrap();
    let outra = nested
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["slug"] == "grupo/sub/outra")
        .unwrap();
    assert_eq!(outra["group"], "grupo/sub");
    assert_eq!(outra["author"], "ai");

    let rule_id = ok(p.cli(&[
        "ideas",
        "add-rule",
        "minha-ideia",
        "Nunca X",
        "--should",
        "--ai",
    ]));
    assert_eq!(rule_id.trim().len(), 36);
    let text = ok(p.cli(&["ideas", "show", "minha-ideia"]));
    assert!(
        text.starts_with("Nova — Explorando\n\ntexto\n\nRegras rascunho:\n"),
        "{text}"
    );
    assert!(
        text.contains(&format!("  {}  ○ Nunca X  ✨\n", &rule_id.trim()[..8])),
        "{text}"
    );
    let shown: Value =
        serde_json::from_str(&ok(p.cli(&["ideas", "show", "minha-ideia", "--json"]))).unwrap();
    assert_eq!(shown["slug"], "minha-ideia");
    assert_eq!(shown["rules"][0]["severity"], "should");
    assert_eq!(shown["dependents"], json!([]));

    // erros: mensagem em stderr, exit 1; valor de enum inválido: exit 64
    let (code, _, err) = p.cli(&["ideas", "show", "nao-existe"]);
    assert_eq!(
        (code, err.as_str()),
        (1, "Error: Ideia não encontrada: nao-existe\n")
    );
    assert_eq!(
        p.cli(&["ideas", "set", "minha-ideia", "--status", "xyz"]).0,
        64
    );
    assert_eq!(p.cli(&["ideas", "depend", "minha-ideia"]).0, 64);
    let (code, _, err) = p.cli(&["ideas", "new", "   "]);
    assert_eq!((code, err.as_str()), (1, "Error: Nome inválido.\n"));
}

#[test]
fn cli_dependencies_and_blockers() {
    let p = Proj::new();
    for t in ["Base", "Topo"] {
        ok(p.cli(&["ideas", "new", t]));
    }
    assert_eq!(
        ok(p.cli(&["ideas", "depend", "topo", "base"])),
        "topo\t1 dependência(s)\n"
    );
    let text = ok(p.cli(&["ideas", "show", "topo"]));
    assert!(
        text.contains("Impedimento: Depende de \"Base\" (nova).\n"),
        "{text}"
    );
    assert!(text.contains("Dependências: "));
    assert!(ok(p.cli(&["ideas", "show", "base"])).contains("Dependentes: topo [new]\n"));
    let (code, _, err) = p.cli(&["ideas", "depend", "base", "topo"]);
    assert_eq!(code, 1);
    assert!(
        err.starts_with("Error: Dependência inválida: o vínculo criaria um ciclo"),
        "{err}"
    );
    assert!(err.ends_with("Nada foi alterado.\n"));
    let (code, _, err) = p.cli(&["ideas", "depend", "topo", "topo"]);
    assert_eq!(code, 1);
    assert!(err.contains("uma ideia não pode depender de si mesma."));
    ok(p.cli(&["ideas", "set", "base", "--status", "done"]));
    assert_eq!(
        ok(p.cli(&["ideas", "undepend", "topo", "base"])),
        "topo\t0 dependência(s)\n"
    );
    assert!(!ok(p.cli(&["ideas", "show", "topo"])).contains("Impedimento"));
}

#[test]
fn cli_promote_and_unpromote() {
    let p = Proj::new();
    ok(p.cli(&["ideas", "new", "Promover"]));
    assert_eq!(
        ok(p.cli(&["ideas", "unpromote", "promover"])),
        "A ideia não estava promovida.\n"
    );
    ok(p.cli(&["ideas", "add-rule", "promover", "Regra um"]));
    // glob sem arquivo: aviso em stderr, mas o glob é copiado
    let idea_file = p.path().join(".vibedeck/ideas/promover.json");
    let mut idea: Value =
        serde_json::from_str(&std::fs::read_to_string(&idea_file).unwrap()).unwrap();
    idea["paths"] = json!(["Sources/Gone/**"]);
    std::fs::write(&idea_file, idea.to_string()).unwrap();
    let (code, out, err) = p.cli(&["ideas", "promote", "promover"]);
    assert_eq!((code, out.as_str()), (0, "promover\n"));
    assert_eq!(
        err,
        "Aviso: globs da ideia que não casam nenhum arquivo foram copiados: Sources/Gone/**\n"
    );
    let topic: Value = serde_json::from_str(
        &std::fs::read_to_string(p.path().join(".vibedeck/rules/promover.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(topic["rules"][0]["text"], "Regra um");
    assert_eq!(topic["sourceIdea"], idea["id"]);
    assert_eq!(topic["paths"], json!(["Sources/Gone/**"]));
    let text = ok(p.cli(&["ideas", "show", "promover"]));
    assert!(text.contains("Promovida para o tópico: promover\n"));
    assert!(text.starts_with("Promover — Aprovada\n"));
    assert_eq!(
        ok(p.cli(&["ideas", "unpromote", "promover"])),
        "Tópico removido: promover\n"
    );
    assert!(!p.path().join(".vibedeck/rules/promover.json").exists());
    ok(p.cli(&["ideas", "promote", "promover"]));
    std::fs::remove_file(p.path().join(".vibedeck/rules/promover.json")).unwrap();
    assert_eq!(
        ok(p.cli(&["ideas", "unpromote", "promover"])),
        "Vínculo removido (o tópico já não existia).\n"
    );
}

#[test]
fn mcp_tools_listing_and_schemas() {
    let p = Proj::new();
    let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
        .arg("-C")
        .arg(p.path())
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
    let find = |n: &str| {
        tools
            .iter()
            .find(|t| t["name"] == n)
            .unwrap_or_else(|| panic!("{n}"))
    };
    for n in [
        "list_ideas",
        "get_idea",
        "add_idea",
        "update_idea",
        "add_idea_rule",
        "promote_idea",
        "unpromote_idea",
    ] {
        find(n);
    }
    assert_eq!(find("list_ideas")["annotations"]["readOnlyHint"], true);
    assert_eq!(find("get_idea")["annotations"]["readOnlyHint"], true);
    assert!(find("add_idea").get("annotations").is_none());
    assert_eq!(
        find("list_ideas")["inputSchema"],
        json!({"type":"object","properties":{"status":{"type":"string","enum":["new","exploring","approved","discarded","done"]}}})
    );
    assert_eq!(
        find("update_idea")["inputSchema"]["required"],
        json!(["idea"])
    );
    assert_eq!(
        find("update_idea")["inputSchema"]["properties"]["dependencies"]["items"],
        json!({"type":"string"})
    );
    assert_eq!(
        find("add_idea_rule")["inputSchema"]["properties"]["severity"]["enum"],
        json!(["must", "should"])
    );
    assert_eq!(
        find("list_ideas")["description"],
        "Ideias, sem força de regra."
    );
    assert_eq!(find("update_idea")["description"], "");
}

#[test]
fn mcp_flow_add_update_rule_promote() {
    let p = Proj::new();
    let r = p.mcp(&[
        ("add_idea", json!({"title":"Nova ideia","body":"b","tags":["x","y"],"reference":"g/nova"})),
        ("add_idea", json!({"title":"Base"})),
        ("add_idea_rule", json!({"idea":"nova","text":"Regra","details":"como","severity":"should"})),
        ("update_idea", json!({"idea":"nova","status":"approved","title":"Titulo","dependencies":["base"],"tags":"p, q"})),
        ("get_idea", json!({"idea":"g/nova"})),
        ("list_ideas", json!({})),
        ("list_ideas", json!({"status":"approved"})),
        ("list_ideas", json!({"status":"bogus"})),
        ("promote_idea", json!({"idea":"nova"})),
        ("unpromote_idea", json!({"idea":"nova"})),
        ("unpromote_idea", json!({"idea":"nova"})),
    ]);
    assert!(r.iter().all(|(e, _)| !e), "{r:?}");
    let added: Value = serde_json::from_str(&r[0].1).unwrap();
    assert_eq!(added["slug"], "g/nova");
    assert_eq!(added["author"], "ai");
    assert_eq!(added["tags"], json!(["x", "y"]));
    let rule: Value = serde_json::from_str(&r[2].1).unwrap();
    assert_eq!(rule["idea"], "g/nova");
    assert_eq!(rule["text"], "Regra");
    assert_eq!(rule["ruleId"].as_str().unwrap().len(), 36);
    let upd: Value = serde_json::from_str(&r[3].1).unwrap();
    assert_eq!(upd["title"], "Titulo");
    assert_eq!(upd["tags"], json!(["p", "q"]));
    assert_eq!(upd["status"], "approved");
    assert_eq!(upd["dependencies"].as_array().unwrap().len(), 1);
    let got: Value = serde_json::from_str(&r[4].1).unwrap();
    assert_eq!(got["rules"][0]["details"], "como");
    assert_eq!(got["rules"][0]["author"], "ai");
    assert_eq!(got["dependencyBlockers"][0]["idea"]["slug"], "base");
    // texto pretty VDJSON, sem newline final
    assert!(r[4].1.starts_with("{\n  \"$schema\" : "));
    assert!(!r[4].1.ends_with('\n'));
    let all: Value = serde_json::from_str(&r[5].1).unwrap();
    let row = |slug: &str| {
        all.as_array()
            .unwrap()
            .iter()
            .find(|r| r["slug"] == slug)
            .unwrap()
    };
    assert_eq!(row("g/nova")["group"], "g");
    assert_eq!(row("g/nova")["rules"], 1);
    assert!(row("g/nova").get("promotedTopic").is_none());
    assert_eq!(row("base")["group"], "");
    assert_eq!(
        serde_json::from_str::<Value>(&r[6].1)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    // status desconhecido no filtro é ignorado: lista tudo
    assert_eq!(
        serde_json::from_str::<Value>(&r[7].1)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        2
    );
    assert_eq!(r[8].1, "Ideia promovida para o tópico de regras: titulo");
    assert_eq!(r[9].1, "Ideia despromovida; tópico removido: titulo");
    assert_eq!(r[10].1, "A ideia não estava promovida.");
}

#[test]
fn mcp_errors_are_is_error_results() {
    let p = Proj::new();
    let r = p.mcp(&[
        ("get_idea", json!({"idea":"nada"})),
        ("get_idea", json!({})),
        ("add_idea", json!({"title":"  "})),
        ("add_idea", json!({"title":"A"})),
        ("update_idea", json!({"idea":"a","status":"zzz"})),
        ("update_idea", json!({"idea":"a","dependencies":["a"]})),
        (
            "update_idea",
            json!({"idea":"a","title":"Mudou","dependencies":["fantasma"]}),
        ),
        (
            "add_idea_rule",
            json!({"idea":"a","text":"x","severity":"nope"}),
        ),
        ("promote_idea", json!({"idea":"nada"})),
        ("unpromote_idea", json!({"idea":"nada"})),
    ]);
    let want = [
        "Ideia não encontrada: nada",
        "Invalid params: Parâmetro obrigatório: idea",
        "Nome inválido.",
        "",
        "Invalid params: Status inválido: zzz",
        "Dependência inválida: uma ideia não pode depender de si mesma. Nada foi alterado.",
        "Dependência inválida: ideia inexistente no projeto: fantasma. Nada foi alterado.",
        "Invalid params: Severidade inválida: nope",
        "Ideia não encontrada: nada",
        "Ideia não encontrada: nada",
    ];
    for (i, w) in want.iter().enumerate() {
        if w.is_empty() {
            assert!(!r[i].0);
        } else {
            assert_eq!((r[i].0, r[i].1.as_str()), (true, *w), "chamada {i}");
        }
    }
    // dependências inválidas não gravam nem o título
    let stored: Value = serde_json::from_str(
        &std::fs::read_to_string(p.path().join(".vibedeck/ideas/a.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(stored["title"], "A");
}
