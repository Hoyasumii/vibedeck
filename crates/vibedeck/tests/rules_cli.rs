//! Integração do binário: `vibedeck rules ...` e `vibedeck hook ...`.

mod rules_common;
use rules_common::{Project, run_bin};
use serde_json::Value;

fn first_line(s: &str) -> &str {
    s.lines().next().unwrap_or("")
}

#[test]
fn topics_and_rules_roundtrip() {
    let p = Project::new();
    let (code, out, _) = p.cli(&[
        "rules",
        "new",
        "Minha Área",
        "--description",
        "d",
        "--path",
        "src/**",
        "--tags",
        "a",
        "b",
    ]);
    assert_eq!((code, out.as_str()), (0, "minha-area\n"));
    let (code, out, _) = p.cli(&[
        "rules",
        "add",
        "minha-area",
        "Sem unwrap",
        "--details",
        "como",
        "--should",
        "--ai",
    ]);
    assert_eq!(code, 0);
    let (id, slug) = first_line(&out).split_once('\t').unwrap();
    assert_eq!(slug, "minha-area");
    assert_eq!(id.len(), 36);
    assert_eq!(id, id.to_uppercase());

    // padrão do grupo = list
    let (_, listed, _) = p.cli(&["rules"]);
    assert_eq!(
        listed,
        "minha-area\tMinha Área\t1 regra(s)\t[src/**]  #a #b\n"
    );
    let (_, json_out, _) = p.cli(&["rules", "--json"]);
    let v: Value = serde_json::from_str(&json_out).unwrap();
    assert_eq!(v[0]["slug"], "minha-area");
    assert_eq!(v[0]["rules"][0]["severity"], "should");

    let (_, shown, _) = p.cli(&["rules", "show", "minha-area"]);
    assert_eq!(
        shown,
        format!(
            "Minha Área [minha-area] — src/**\nd\n  {}  ○ Sem unwrap  ✨\n",
            &id[..8]
        )
    );

    // cria tópico na hora e remove por prefixo
    let (_, out2, _) = p.cli(&["rules", "add", "Geral", "Regra x"]);
    let id2 = first_line(&out2).split('\t').next().unwrap().to_string();
    let (code, out3, _) = p.cli(&["rules", "remove", &id2[..8]]);
    assert_eq!((code, out3.as_str()), (0, ""));
    let (code, _, err) = p.cli(&["rules", "remove", "zzzzzz"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "Error: Regra não encontrada entre as aplicáveis: zzzzzz\n"
    );
    let (code, _, err) = p.cli(&["rules", "show", "nada"]);
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: "), "{err}");
}

#[test]
fn for_filters_by_files_and_manual_flag() {
    let p = Project::new();
    p.cli(&["rules", "new", "Global"]);
    p.cli(&["rules", "new", "Docs", "--path", "docs/**"]);
    let (_, out, _) = p.cli(&["rules", "add", "global", "Manual"]);
    let manual_id = first_line(&out).split('\t').next().unwrap().to_string();
    p.cli(&["rules", "add", "docs", "Escrita"]);
    let (_, out, _) = p.cli(&["rules", "for"]);
    assert_eq!(
        out,
        format!("## Global [global]\n  {}  ● Manual\n", &manual_id[..8])
    );
    let (_, out, _) = p.cli(&["rules", "for", "docs/a.md"]);
    assert!(out.contains("## Docs [docs]"));
    let (_, out, _) = p.cli(&["rules", "for", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["manualRules"], 1);
    assert_eq!(v[0]["rules"].as_array().unwrap().len(), 0);
    let (_, out, _) = p.cli(&["rules", "for", "--json", "--manual"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v[0]["manualRules"], Value::Null);
    assert_eq!(v[0]["rules"][0]["check"], "manual");
    let (_, out, _) = p.cli(&["rules", "--help"]);
    assert!(out.contains("set-test"));
}

#[test]
fn set_test_validation_and_test_run() {
    let p = Project::new();
    let (_, out, _) = p.cli(&["rules", "add", "Geral", "Roda ok"]);
    let ok = first_line(&out).split('\t').next().unwrap().to_string();
    let (_, out, _) = p.cli(&["rules", "add", "Geral", "Roda falha", "--should"]);
    let bad = first_line(&out).split('\t').next().unwrap().to_string();
    let (_, out, _) = p.cli(&["rules", "add", "Geral", "Roda must"]);
    let must = first_line(&out).split('\t').next().unwrap().to_string();

    let (code, _, err) = p.cli(&["rules", "set-test", &ok]);
    assert_eq!(code, 64);
    assert!(err.contains("Use exatamente um de --command, --manual ou --clear."));
    let (code, _, _) = p.cli(&["rules", "set-test", &ok, "--manual", "--clear"]);
    assert_eq!(code, 64);

    let (code, out, _) = p.cli(&["rules", "set-test", &ok, "--command", "exit 0"]);
    assert_eq!((code, out), (0, format!("{}\tScript\n", &ok[..8])));
    p.cli(&["rules", "set-test", &bad, "--command", "echo ruim; exit 3"]);
    let (_, out, _) = p.cli(&["rules", "test"]);
    assert!(
        out.contains(&format!("✅ [geral] {} Roda ok  (exit 0)", &ok[..8])),
        "{out}"
    );
    assert!(
        out.contains(&format!(
            "❌ [geral] {} Roda falha  (exit 3)\n    ruim\n",
            &bad[..8]
        )),
        "{out}"
    );
    // should reprovado não derruba o exit
    let (code, _, _) = p.cli(&["rules", "test"]);
    assert_eq!(code, 0);
    p.cli(&["rules", "set-test", &must, "--command", "exit 2"]);
    let (code, _, _) = p.cli(&["rules", "test"]);
    assert_eq!(code, 1);
    // com --json a saída não muda o exit (como o Swift)
    let (code, out, _) = p.cli(&["rules", "test", "--json"]);
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v.as_array().unwrap().len(), 3);
    assert_eq!(v[2]["exitCode"], 2);
    assert_eq!(v[2]["verdict"], "fail");

    let (code, out, _) = p.cli(&["rules", "set-test", &must, "--clear"]);
    assert_eq!((code, out), (0, format!("{}\tSem teste\n", &must[..8])));
}

#[test]
fn check_runs_scripts_and_records() {
    let p = Project::new();
    let (_, out, _) = p.cli(&["rules", "add", "Geral", "Passa"]);
    let ok = first_line(&out).split('\t').next().unwrap().to_string();
    let (_, out, _) = p.cli(&["rules", "add", "Geral", "Manual"]);
    let manual = first_line(&out).split('\t').next().unwrap().to_string();
    p.cli(&["rules", "set-test", &ok, "--command", "exit 0"]);

    let (code, out, _) = p.cli(&["rules", "check", "--task", "t1"]);
    assert_eq!(code, 0);
    assert_eq!(
        out,
        "✅ Aprovado (1 regra(s), 1 por script)\n  ⏭ 1 regra(s) manual(is) não verificada(s) (use --manual)\n"
    );
    // --manual exige respostas
    let (code, _, err) = p.cli_in(
        p.path(),
        &["rules", "check", "--task", "t2", "--manual"],
        "[]",
    );
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: Check incompleto"), "{err}");
    let answers = format!(
        "[{{\"ruleId\":\"{}\",\"verdict\":\"fail\",\"note\":\"n\"}}]",
        &manual[..8]
    );
    let (code, out, _) = p.cli_in(
        p.path(),
        &["rules", "check", "--task", "t2", "--manual", "--ai"],
        &answers,
    );
    assert_eq!(code, 1);
    assert!(out.starts_with("❌ Reprovado\n  ✗ Manual\n"), "{out}");
    let (code, out, _) = p.cli(&[
        "rules",
        "check",
        "--task",
        "t3",
        "--results",
        &answers.replace("fail", "pass"),
        "--json",
    ]);
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["passed"], true);
    assert_eq!(v["task"], "t3");

    let (_, out, _) = p.cli(&["rules", "checks", "--limit", "2"]);
    assert_eq!(out.lines().count(), 2);
    assert!(out.lines().next().unwrap().ends_with("✅  t3"), "{out}");
    let (_, out, _) = p.cli(&["rules", "checks", "--topic", "geral", "--json"]);
    assert_eq!(
        serde_json::from_str::<Value>(&out)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        3
    );
    assert_eq!(
        std::fs::read_dir(p.path().join(".vibedeck/checks"))
            .unwrap()
            .count(),
        3
    );
    let (code, _, err) = p.cli(&["rules", "check", "--task", "x", "--results", "{"]);
    assert_eq!(code, 1);
    assert!(err.starts_with("Error: "));
}

#[test]
fn hook_install_status_uninstall() {
    let p = Project::new();
    let (code, out, _) = p.cli(&["hook", "install"]);
    let local = p.path().join(".claude/settings.local.json");
    // O CLI imprime o caminho canônico da raiz (no macOS, /var é link para /private/var).
    let shown = std::fs::canonicalize(p.path())
        .unwrap()
        .join(".claude/settings.local.json");
    assert_eq!(
        (code, out),
        (0, format!("Hook ligado em {}.\n", shown.display()))
    );
    let settings: Value = serde_json::from_slice(&std::fs::read(&local).unwrap()).unwrap();
    let cmd = settings["hooks"]["Stop"][0]["hooks"][0]["command"]
        .as_str()
        .unwrap();
    assert!(
        cmd.starts_with('\'') && cmd.ends_with("' hook stop"),
        "{cmd}"
    );
    assert!(settings["hooks"].get("SessionStart").is_none());

    let (_, out, _) = p.cli(&["hook"]);
    assert!(
        out.contains(&format!("claude local: ligado ({})", shown.display())),
        "{out}"
    );
    assert!(out.contains("claude project: desligado"));
    assert!(out.contains("codex project: desligado"));
    assert!(!out.contains("codex local"));
    assert!(out.ends_with("Nenhuma alteração pendente de check.\n"));
    let (_, out, _) = p.cli(&["hook", "status", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["hooks"].as_array().unwrap().len(), 3);
    assert_eq!(v["hooks"][0]["on"], true);
    assert_eq!(v["unverified"].as_array().unwrap().len(), 0);

    let (code, out, _) = p.cli(&["hook", "install", "-a", "codex"]);
    let codex = std::fs::canonicalize(p.path())
        .unwrap()
        .join(".codex/hooks.json");
    assert_eq!(code, 0);
    assert!(out.starts_with(&format!(
        "Hook ligado em {}.\nNo Codex, aprove",
        codex.display()
    )));
    let settings: Value = serde_json::from_slice(&std::fs::read(&codex).unwrap()).unwrap();
    assert_eq!(
        settings["hooks"]["Stop"][0]["hooks"][0]["command"],
        "'vibedeck' hook stop"
    );
    assert_eq!(
        settings["hooks"]["SessionStart"][0]["hooks"][0]["command"],
        "'vibedeck' hook start"
    );

    let (code, _, err) = p.cli(&["hook", "install", "-a", "codex", "-s", "local"]);
    assert_eq!(code, 1);
    assert!(err.contains("O Codex não tem um arquivo de hooks só seu por projeto."));
    let (code, _, err) = p.cli(&["hook", "uninstall", "--agent", "codex", "--scope", "local"]);
    assert_eq!(code, 1);
    assert!(err.contains("O Codex só tem o escopo project (.codex/hooks.json)."));

    let (code, out, _) = p.cli(&["hook", "uninstall"]);
    assert_eq!(
        (code, out),
        (
            0,
            format!("Hook do VibeDeck removido de {}.\n", shown.display())
        )
    );
    let (_, out, _) = p.cli(&["hook", "status", "--json"]);
    let v: Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v["hooks"][0]["on"], false);
    assert_eq!(v["hooks"][2]["on"], true);
}

fn git(dir: &std::path::Path, args: &[&str]) {
    let st = std::process::Command::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_AUTHOR_NAME", "t")
        .env("GIT_AUTHOR_EMAIL", "t@t")
        .env("GIT_COMMITTER_NAME", "t")
        .env("GIT_COMMITTER_EMAIL", "t@t")
        .output()
        .unwrap();
    assert!(
        st.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&st.stderr)
    );
}

#[test]
fn hook_stop_blocks_then_releases_and_passes_after_check() {
    let p = Project::new();
    git(p.path(), &["init", "-q"]);
    p.cli(&["rules", "add", "Geral", "Regra manual", "--should"]);
    git(p.path(), &["add", "."]);
    git(p.path(), &["commit", "-qm", "init"]);
    let tmp = std::env::temp_dir().join(format!("vibedeck-hook-tmp-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let tmp_s = tmp.to_str().unwrap();
    std::fs::write(p.path().join("novo.rs"), "fn main() {}").unwrap();
    let input = format!(
        "{{\"session_id\":\"s1\",\"transcript_path\":null,\"cwd\":\"{}\"}}",
        p.path().display()
    );
    let stop = || {
        run_bin(
            &["hook", "stop", "--max-blocks", "2"],
            &tmp,
            &input,
            &[("TMPDIR", tmp_s)],
        )
    };

    // sem -C e fora de projeto o cwd do JSON é quem manda
    let (code, out, _) = stop();
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(v["decision"], "block");
    assert!(v["reason"].as_str().unwrap().contains("novo.rs"));
    assert!(tmp.join("vibedeck-count-s1").exists());
    stop();
    let (_, out, _) = stop();
    let v: Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(
        v["systemMessage"],
        "⚠️ VibeDeck: o agente parou sem check de regras aprovado para: novo.rs"
    );
    assert!(!tmp.join("vibedeck-count-s1").exists());

    // com check aprovado depois da alteração, o hook libera e limpa o contador
    p.cli(&["rules", "check", "--task", "ok", "--file", "novo.rs"]);
    let (code, out, _) = stop();
    assert_eq!((code, out.as_str()), (0, ""));

    // fora de projeto: silencioso
    let (code, out, _) = run_bin(
        &["hook", "stop"],
        &tmp,
        "{\"session_id\":\"s2\",\"cwd\":\"/\"}",
        &[("TMPDIR", tmp_s)],
    );
    assert_eq!((code, out.as_str()), (0, ""));

    // hook start cria a marca uma vez
    let (code, out, _) = run_bin(
        &["hook", "start"],
        &tmp,
        "{\"session_id\":\"abc\"}",
        &[("TMPDIR", tmp_s)],
    );
    assert_eq!((code, out.as_str()), (0, ""));
    assert!(tmp.join("vibedeck-start-abc").exists());
    let _ = std::fs::remove_dir_all(&tmp);
}
