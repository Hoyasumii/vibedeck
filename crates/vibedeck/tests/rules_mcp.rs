//! Integração do servidor MCP real: tools de regras (mcp.md §4.4).

mod rules_common;
use rules_common::Project;
use serde_json::{Value, json};

fn parse(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|e| panic!("{e}: {text}"))
}

#[test]
fn tools_are_listed_with_schema_and_hints() {
    let p = Project::new();
    let tools = p.tools_list();
    let names: Vec<&str> = tools.iter().filter_map(|t| t["name"].as_str()).collect();
    for n in [
        "rules_for",
        "submit_rule_check",
        "run_rule_tests",
        "set_rule_test",
        "list_rule_topics",
        "get_rule_topic",
        "add_rule_topic",
        "add_rule",
        "move_rule_to_group",
        "rename_rule_group",
    ] {
        assert!(names.contains(&n), "{n} ausente em {names:?}");
    }
    let by = |n: &str| tools.iter().find(|t| t["name"] == n).unwrap();
    assert_eq!(by("rules_for")["annotations"]["readOnlyHint"], true);
    assert_eq!(by("run_rule_tests")["annotations"]["readOnlyHint"], true);
    assert_eq!(by("list_rule_topics")["annotations"]["readOnlyHint"], true);
    assert!(by("submit_rule_check").get("annotations").is_none());
    assert_eq!(by("list_rule_topics")["description"], "");
    assert_eq!(
        by("submit_rule_check")["inputSchema"]["required"],
        json!(["task"])
    );
    assert_eq!(
        by("submit_rule_check")["inputSchema"]["properties"]["results"]["items"]["properties"]["verdict"]
            ["enum"],
        json!(["pass", "fail", "na"])
    );
    assert_eq!(
        by("set_rule_test")["inputSchema"]["properties"]["mode"]["enum"],
        json!(["script", "manual"])
    );
    assert_eq!(
        by("add_rule")["inputSchema"]["properties"]["severity"]["enum"],
        json!(["must", "should"])
    );
}

#[test]
fn topics_and_rules_tools() {
    let p = Project::new();
    let (err, text) = p.tool(
        "add_rule_topic",
        json!({"title": "Backend", "paths": ["src/**"], "tags": "a, b", "description": "d"}),
    );
    assert!(!err, "{text}");
    let v = parse(&text);
    assert_eq!(v["slug"], "backend");
    assert_eq!(v["paths"], json!(["src/**"]));

    let (_, text) = p.tool(
        "add_rule",
        json!({"topic": "backend", "text": "Sem panic", "details": "grep", "severity": "should"}),
    );
    let v = parse(&text);
    assert_eq!(v["topic"], "backend");
    assert_eq!(v["text"], "Sem panic");
    let rule_id = v["ruleId"].as_str().unwrap().to_string();
    assert_eq!(rule_id.len(), 36);

    let (err, text) = p.tool(
        "add_rule",
        json!({"topic": "backend", "text": "x", "severity": "mid"}),
    );
    assert!(err);
    assert_eq!(text, "Invalid params: Severidade inválida: mid");
    let (err, text) = p.tool("add_rule", json!({"topic": "backend"}));
    assert!(err);
    assert!(text.contains("Parâmetro obrigatório: text"));

    let (_, text) = p.tool("list_rule_topics", json!({}));
    assert_eq!(
        parse(&text),
        json!([{"slug":"backend","title":"Backend","description":"d","tags":["a","b"],"paths":["src/**"],"rules":1}])
    );
    let (_, text) = p.tool("get_rule_topic", json!({"topic": "Backend"}));
    let v = parse(&text);
    assert_eq!(v["rules"][0]["ruleId"], rule_id);
    assert_eq!(v["rules"][0]["check"], "manual");
    assert_eq!(v["rules"][0]["details"], "grep");
    let (err, _) = p.tool("get_rule_topic", json!({"topic": "nada"}));
    assert!(err);

    // set_rule_test
    let (_, text) = p.tool(
        "set_rule_test",
        json!({"rule_id": &rule_id[..8], "mode": "script", "command": "exit 0"}),
    );
    assert_eq!(text, format!("Regra {}: Script.", &rule_id[..8]));
    let (_, text) = p.tool(
        "set_rule_test",
        json!({"rule_id": &rule_id[..8], "mode": "manual", "reason": "r"}),
    );
    assert_eq!(text, format!("Regra {}: Manual.", &rule_id[..8]));
    let (err, text) = p.tool(
        "set_rule_test",
        json!({"rule_id": &rule_id[..8], "mode": "x"}),
    );
    assert!(err);
    assert_eq!(text, "Invalid params: mode deve ser script ou manual.");
    let (err, text) = p.tool(
        "set_rule_test",
        json!({"rule_id": &rule_id[..8], "mode": "script"}),
    );
    assert!(err);
    assert_eq!(
        text,
        "Teste de regra inválido: Informe o comando do script."
    );

    // grupos de regras
    let (_, text) = p.tool(
        "move_rule_to_group",
        json!({"rule": &rule_id[..8], "group": "Meu Grupo/Sub"}),
    );
    assert_eq!(parse(&text)["group"], "meu-grupo/sub");
    let (_, text) = p.tool(
        "rename_rule_group",
        json!({"topic": "backend", "from": "meu-grupo", "to": "outro"}),
    );
    assert_eq!(text, "Grupo de regras movido.");
    let on_disk = std::fs::read_to_string(p.path().join(".vibedeck/rules/backend.json")).unwrap();
    assert!(on_disk.contains("\"group\" : \"outro/sub\""), "{on_disk}");
    let (err, _) = p.tool(
        "rename_rule_group",
        json!({"topic": "backend", "from": "outro", "to": "outro/x"}),
    );
    assert!(err);
}

#[test]
fn rules_for_compact_output_and_scripts() {
    let p = Project::new();
    // sem regras
    let (err, text) = p.tool("rules_for", json!({"files": ["a.rs"]}));
    assert!(!err);
    assert_eq!(
        text,
        "Nenhuma regra aplicável a esses arquivos. Mesmo assim, chame submit_rule_check com results=[] para registrar a tarefa."
    );

    let (_, t) = p.tool("add_rule", json!({"topic": "Geral", "text": "Script ok"}));
    let ok = parse(&t)["ruleId"].as_str().unwrap().to_string();
    let (_, t) = p.tool(
        "add_rule",
        json!({"topic": "Geral", "text": "Manual", "severity": "should"}),
    );
    let manual = parse(&t)["ruleId"].as_str().unwrap().to_string();
    p.tool(
        "set_rule_test",
        json!({"rule_id": ok, "mode": "script", "command": "echo \"$VIBEDECK_FILES\"; exit 0"}),
    );

    let (_, text) = p.tool("rules_for", json!({}));
    assert!(
        !text.contains('\n') && !text.contains(": "),
        "compacto: {text}"
    );
    assert_eq!(
        text,
        format!(
            "[{{\"manualRules\":1,\"rules\":[{{\"check\":\"script\",\"ruleId\":\"{}\",\"severity\":\"must\",\"text\":\"Script ok\"}}],\"slug\":\"geral\",\"title\":\"Geral\"}}]",
            &ok[..8]
        )
    );
    let (_, text) = p.tool("rules_for", json!({"include_manual": true}));
    assert!(text.contains(&manual[..8]));
    let (_, text) = p.tool("rules_for", json!({"verbose": true}));
    assert!(text.contains("\n  "), "verbose usa JSON pretty");
    assert_eq!(parse(&text)[0]["rules"][0]["ruleId"], ok);

    // run_rule_tests
    let (_, text) = p.tool("run_rule_tests", json!({"topics": ["geral"]}));
    let v = parse(&text);
    assert_eq!(v.as_array().unwrap().len(), 1);
    assert_eq!(v[0]["verdict"], "pass");
    assert_eq!(v[0]["exitCode"], 0);
    let (_, text) = p.tool("run_rule_tests", json!({}));
    assert_eq!(text, "Nenhuma regra aplicável tem script.");

    // submit_rule_check: manual pendente
    let (err, text) = p.tool("submit_rule_check", json!({"task": "t", "files": ["a.rs"]}));
    assert!(!err);
    assert!(
        text.starts_with("✅ Check aprovado (1 regra(s))."),
        "{text}"
    );
    assert!(text.contains("⏭️ 1 regra(s) manual(is) não verificada(s) (peça verify_manual=true para checá-las): Manual"));
    assert!(text.contains("⚙️ 1 regra(s) decidida(s) por script."));
    assert!(text.contains(".vibedeck/checks/"));

    let (err, text) = p.tool(
        "submit_rule_check",
        json!({"task": "t", "verify_manual": true}),
    );
    assert!(err);
    assert!(text.starts_with("Check incompleto:"), "{text}");

    // results como array e como string JSON
    let answers = json!([{"ruleId": &manual[..8], "verdict": "fail", "note": "n"}]);
    let (_, text) = p.tool(
        "submit_rule_check",
        json!({"task": "t", "verify_manual": true, "results": answers}),
    );
    assert!(text.contains("⚠️ Recomendações não cumpridas"), "{text}");
    assert!(text.contains("- Manual"));
    let (_, text) = p.tool("submit_rule_check", json!({"task": "t", "verify_manual": true, "results": answers.to_string(), "verbose": true}));
    assert!(text.contains("\"passed\" : true"), "{text}");
    let (err, text) = p.tool(
        "submit_rule_check",
        json!({"task": "t", "results": "nao-json"}),
    );
    assert!(err);
    assert_eq!(
        text,
        "Invalid params: results deve ser uma lista de {ruleId, verdict: pass|fail|na, note}."
    );
    assert_eq!(
        std::fs::read_dir(p.path().join(".vibedeck/checks"))
            .unwrap()
            .count(),
        3
    );
}

#[test]
fn failed_must_script_reports_output() {
    let p = Project::new();
    let (_, t) = p.tool("add_rule", json!({"topic": "Geral", "text": "Quebra"}));
    let id = parse(&t)["ruleId"].as_str().unwrap().to_string();
    p.tool(
        "set_rule_test",
        json!({"rule_id": id, "mode": "script", "command": "echo motivo-x; exit 4"}),
    );
    let (_, text) = p.tool("submit_rule_check", json!({"task": "t"}));
    assert!(
        text.starts_with(
            "❌ Check reprovado. Corrija e envie um novo check antes de concluir:\n- Quebra"
        ),
        "{text}"
    );
    assert!(
        text.contains("--- script reprovado:\necho motivo-x; exit 4 (exit 4)\nmotivo-x"),
        "{text}"
    );
}
