//! `mcp install|uninstall` (registro do servidor MCP no Claude Code e no Codex) com `claude` falso.
//!
//! Um único teste: ele muda variáveis de ambiente do processo (`VIBEDECK_CLAUDE_BIN`, `HOME`).

use std::fs;
use std::os::unix::fs::PermissionsExt;

use vibedeck_core::ai::Provider;
use vibedeck_core::ai::mcp_install::{self, Scope};

#[test]
fn registra_e_remove_no_claude_e_no_codex() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("proj");
    let home = dir.path().join("home");
    fs::create_dir_all(&root).unwrap();
    fs::create_dir_all(&home).unwrap();
    let log = dir.path().join("log.txt");
    let status = dir.path().join("status.txt");
    let script = dir.path().join("claude");
    fs::write(
        &script,
        format!(
            "#!/bin/sh\necho \"$(pwd) $*\" >> '{}'\nexit $(cat '{}')\n",
            log.display(),
            status.display()
        ),
    )
    .unwrap();
    fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(&status, "0").unwrap();
    // SAFETY: único teste deste binário; nenhuma outra thread lê o ambiente.
    unsafe {
        std::env::set_var("VIBEDECK_CLAUDE_BIN", &script);
        std::env::set_var("HOME", &home);
        std::env::set_var("SHELL", "/bin/sh");
    }
    let lines = || fs::read_to_string(&log).unwrap_or_default();
    let real_root = fs::canonicalize(&root).unwrap();
    let cwd = real_root.display().to_string();

    // padrão: escopo local com o caminho absoluto
    let out = mcp_install::install(
        &root,
        Provider::Claude,
        None,
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap();
    assert_eq!(out.code, 0);
    assert_eq!(
        out.stdout,
        "Reinicie o Claude Code (ou use /mcp) para carregar as tools do VibeDeck.\n"
    );
    assert_eq!(
        lines(),
        format!("{cwd} mcp add vibedeck -s local -- /abs/vibedeck mcp\n")
    );

    // project: `.mcp.json` é versionado, então vai `vibedeck` do PATH; --force remove antes
    let _ = fs::remove_file(&log);
    let out = mcp_install::install(
        &root,
        Provider::Claude,
        Some(Scope::Project),
        "meu",
        true,
        "/abs/vibedeck",
    )
    .unwrap();
    assert_eq!(out.code, 0);
    assert_eq!(
        lines(),
        format!("{cwd} mcp remove meu -s project\n{cwd} mcp add meu -s project -- vibedeck mcp\n")
    );

    // falha do `claude mcp add`: mensagem e o mesmo código de saída
    fs::write(&status, "3").unwrap();
    let out = mcp_install::install(
        &root,
        Provider::Claude,
        Some(Scope::User),
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap();
    assert_eq!(out.code, 3);
    assert_eq!(out.stdout, "");
    assert_eq!(
        out.stderr,
        "`claude mcp add` falhou. Se já existe um servidor \"vibedeck\", use --force.\n"
    );

    // uninstall repassa o código do claude, sem mensagem
    let _ = fs::remove_file(&log);
    let out =
        mcp_install::uninstall(&root, Provider::Claude, Some(Scope::User), "vibedeck").unwrap();
    assert_eq!(
        (out.code, out.stdout.as_str(), out.stderr.as_str()),
        (3, "", "")
    );
    assert_eq!(lines(), format!("{cwd} mcp remove vibedeck -s user\n"));
    fs::write(&status, "0").unwrap();
    assert_eq!(
        mcp_install::uninstall(&root, Provider::Claude, None, "vibedeck")
            .unwrap()
            .code,
        0
    );

    // Codex: bloco gerenciado no config.toml do projeto (padrão) ou da home (user)
    let out = mcp_install::install(
        &root,
        Provider::Codex,
        None,
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap();
    assert_eq!(
        out.stdout,
        "MCP instalado no Codex (project). Reinicie o cliente para carregar as tools.\n"
    );
    let config = fs::read_to_string(root.join(".codex/config.toml")).unwrap();
    assert!(config.contains("[mcp_servers.vibedeck]"));
    assert!(config.contains("command = \"/abs/vibedeck\""));
    assert!(config.contains(&format!("\"--root\", \"{}\"", root.display())));
    let again = mcp_install::install(
        &root,
        Provider::Codex,
        None,
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap_err();
    assert_eq!(
        again.to_string(),
        "Codex: MCP vibedeck já instalado; use --force."
    );
    mcp_install::install(
        &root,
        Provider::Codex,
        Some(Scope::User),
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap();
    assert!(home.join(".codex/config.toml").is_file());
    assert_eq!(
        mcp_install::uninstall(&root, Provider::Codex, None, "vibedeck")
            .unwrap()
            .code,
        0
    );
    assert!(
        !fs::read_to_string(root.join(".codex/config.toml"))
            .unwrap()
            .contains("mcp_servers")
    );
    assert!(
        fs::read_to_string(home.join(".codex/config.toml"))
            .unwrap()
            .contains("mcp_servers")
    );

    // `claude` ausente
    unsafe { std::env::set_var("VIBEDECK_CLAUDE_BIN", dir.path().join("nao-existe")) };
    let out = mcp_install::install(
        &root,
        Provider::Claude,
        None,
        "vibedeck",
        false,
        "/abs/vibedeck",
    )
    .unwrap();
    assert_eq!(out.code, 1);
    assert!(
        out.stderr
            .starts_with("Não foi possível executar `claude`: "),
        "{}",
        out.stderr
    );
}
