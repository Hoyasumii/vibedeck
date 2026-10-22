//! Registro do servidor MCP do VibeDeck nos agentes: Claude Code (`claude mcp add|remove`) e Codex
//! (bloco gerenciado em `.codex/config.toml`), como `MCPInstall`/`MCPUninstall` e `CodexMCP` no Swift.
//!
//! Divergência intencional: o Swift registrava o Codex via `python3 -c <adaptador>` porque o SDK Swift MCP
//! rejeitava capacidades experimentais em objeto; o servidor Rust não tem essa limitação, então o bloco
//! aponta direto para `vibedeck mcp --root <raiz>`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use super::{AiError, Provider, Result, home_dir, provider};
use crate::store::write_atomic;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Local,
    Project,
    User,
}

impl Scope {
    pub fn parse(s: &str) -> Option<Scope> {
        match s {
            "local" => Some(Scope::Local),
            "project" => Some(Scope::Project),
            "user" => Some(Scope::User),
            _ => None,
        }
    }

    pub fn raw(self) -> &'static str {
        match self {
            Scope::Local => "local",
            Scope::Project => "project",
            Scope::User => "user",
        }
    }
}

/// Resultado de install/uninstall: o que imprimir e o código de saída.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Outcome {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

fn managed_markers(name: &str) -> (String, String) {
    (
        format!("# BEGIN VibeDeck MCP {name}\n"),
        format!("# END VibeDeck MCP {name}\n"),
    )
}

fn managed_range(text: &str, begin: &str, end: &str) -> Option<std::ops::Range<usize>> {
    let start = text.find(begin)?;
    let after = start + begin.len();
    let stop = text[after..].find(end)? + after + end.len();
    Some(start..stop)
}

fn codex_config(root: &Path, user: bool, home: &Path) -> PathBuf {
    (if user { home } else { root }).join(".codex/config.toml")
}

fn literal(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".into())
}

/// Bloco gerenciado do Codex: preserva o resto do arquivo; `force` troca um bloco existente.
pub fn codex_install(
    root: &Path,
    cli: &str,
    name: &str,
    user: bool,
    force: bool,
    home: &Path,
) -> Result<()> {
    if name.is_empty()
        || !name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(AiError::CodexServer("Nome MCP inválido".into()));
    }
    let file = codex_config(root, user, home);
    let mut text = fs::read_to_string(&file).unwrap_or_default();
    let (begin, end) = managed_markers(name);
    if let Some(range) = managed_range(&text, &begin, &end) {
        if !force {
            return Err(AiError::CodexServer(format!(
                "MCP {name} já instalado; use --force."
            )));
        }
        text.replace_range(range, "");
    }
    if text.contains(&format!("[mcp_servers.{name}]"))
        || text.contains(&format!("[mcp_servers.\"{name}\"]"))
    {
        return Err(AiError::CodexServer(format!(
            "Já existe uma configuração MCP manual para {name}. Remova ou renomeie esse registro antes de instalar."
        )));
    }
    let args = ["mcp", "--root", &root.to_string_lossy()]
        .iter()
        .map(|a| literal(a))
        .collect::<Vec<_>>()
        .join(", ");
    text.push_str(&format!(
        "\n{begin}[mcp_servers.{name}]\ncommand = {}\nargs = [{args}]\n{end}",
        literal(cli)
    ));
    write_atomic(&file, text.as_bytes())?;
    Ok(())
}

pub fn codex_uninstall(root: &Path, name: &str, user: bool, home: &Path) -> Result<()> {
    let file = codex_config(root, user, home);
    let Ok(mut text) = fs::read_to_string(&file) else {
        return Ok(());
    };
    let (begin, end) = managed_markers(name);
    let Some(range) = managed_range(&text, &begin, &end) else {
        return Ok(());
    };
    text.replace_range(range, "");
    write_atomic(&file, text.as_bytes())?;
    Ok(())
}

/// Roda `claude <args>` em `dir` (stdout/stderr herdados). `Err` = não foi possível executar.
pub fn run_claude(args: &[&str], dir: &Path) -> std::result::Result<i32, String> {
    let exe = std::env::var_os(Provider::Claude.env_override())
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| Provider::Claude.executable())
        .unwrap_or_else(|| PathBuf::from("claude"));
    let status = Command::new(exe)
        .args(args)
        .current_dir(dir)
        .env("PATH", provider::child_path())
        .status()
        .map_err(|e| e.to_string())?;
    Ok(status.code().unwrap_or(1))
}

/// `vibedeck mcp install`. `cli` é o caminho do executável a registrar (escopo `project` usa `vibedeck`
/// do PATH, pois o `.mcp.json` é versionado).
pub fn install(
    root: &Path,
    provider: Provider,
    scope: Option<Scope>,
    name: &str,
    force: bool,
    cli: &str,
) -> Result<Outcome> {
    let scope = scope.unwrap_or(if provider == Provider::Codex {
        Scope::Project
    } else {
        Scope::Local
    });
    if provider == Provider::Codex {
        if scope == Scope::Local {
            return Err(AiError::Message(
                "Codex suporta os escopos project ou user.".into(),
            ));
        }
        codex_install(root, cli, name, scope == Scope::User, force, &home_dir())?;
        return Ok(Outcome {
            code: 0,
            stdout: format!(
                "MCP instalado no Codex ({}). Reinicie o cliente para carregar as tools.\n",
                scope.raw()
            ),
            stderr: String::new(),
        });
    }
    let executable = if scope == Scope::Project {
        "vibedeck"
    } else {
        cli
    };
    let launch_failed = |e: String| Outcome {
        code: 1,
        stdout: String::new(),
        stderr: format!("Não foi possível executar `claude`: {e}\n"),
    };
    if force {
        match run_claude(&["mcp", "remove", name, "-s", scope.raw()], root) {
            Ok(_) => {}
            Err(e) => return Ok(launch_failed(e)),
        }
    }
    let status = match run_claude(
        &[
            "mcp",
            "add",
            name,
            "-s",
            scope.raw(),
            "--",
            executable,
            "mcp",
        ],
        root,
    ) {
        Ok(s) => s,
        Err(e) => return Ok(launch_failed(e)),
    };
    if status != 0 {
        return Ok(Outcome {
            code: status,
            stdout: String::new(),
            stderr: format!(
                "`claude mcp add` falhou. Se já existe um servidor \"{name}\", use --force.\n"
            ),
        });
    }
    Ok(Outcome {
        code: 0,
        stdout: "Reinicie o Claude Code (ou use /mcp) para carregar as tools do VibeDeck.\n".into(),
        stderr: String::new(),
    })
}

/// `vibedeck mcp uninstall`.
pub fn uninstall(
    root: &Path,
    provider: Provider,
    scope: Option<Scope>,
    name: &str,
) -> Result<Outcome> {
    let scope = scope.unwrap_or(if provider == Provider::Codex {
        Scope::Project
    } else {
        Scope::Local
    });
    if provider == Provider::Codex {
        if scope == Scope::Local {
            return Err(AiError::Message("Codex suporta project ou user.".into()));
        }
        codex_uninstall(root, name, scope == Scope::User, &home_dir())?;
        return Ok(Outcome::default());
    }
    match run_claude(&["mcp", "remove", name, "-s", scope.raw()], root) {
        Ok(code) => Ok(Outcome {
            code,
            ..Outcome::default()
        }),
        Err(e) => Ok(Outcome {
            code: 1,
            stdout: String::new(),
            stderr: format!("Não foi possível executar `claude`: {e}\n"),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_do_codex_preserva_configuracao_do_usuario() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let file = root.join(".codex/config.toml");
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        let original = "model = 'my-model'\n[mcp_servers.docs]\ncommand = 'docs'\n";
        fs::write(&file, original).unwrap();
        let home = root.join("home");
        codex_install(
            root,
            "/tmp/bin with spaces/vibedeck",
            "vibedeck",
            false,
            false,
            &home,
        )
        .unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.starts_with(original));
        assert!(text.contains("/tmp/bin with spaces/vibedeck"));
        assert!(text.contains("--root"));
        assert!(codex_install(root, "/tmp/cli", "vibedeck", false, false, &home).is_err());
        codex_install(root, "/tmp/new", "vibedeck", false, true, &home).unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert_eq!(text.matches("[mcp_servers.vibedeck]").count(), 1);
        assert!(text.contains("/tmp/new"));
        codex_uninstall(root, "vibedeck", false, &home).unwrap();
        assert_eq!(fs::read_to_string(&file).unwrap().trim(), original.trim());
    }

    #[test]
    fn nome_invalido_e_registro_manual_recusados() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("h");
        assert!(codex_install(dir.path(), "x", "a b", false, false, &home).is_err());
        let file = dir.path().join(".codex/config.toml");
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(&file, "[mcp_servers.vibedeck]\ncommand='x'\n").unwrap();
        let err = codex_install(dir.path(), "x", "vibedeck", false, true, &home)
            .unwrap_err()
            .to_string();
        assert!(err.contains("configuração MCP manual"), "{err}");
    }

    #[test]
    fn escopo_user_grava_na_home() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        codex_install(dir.path(), "/bin/vibedeck", "vibedeck", true, false, &home).unwrap();
        assert!(home.join(".codex/config.toml").is_file());
        assert!(!dir.path().join(".codex/config.toml").exists());
    }

    #[test]
    fn codex_local_e_recusado() {
        let dir = tempfile::tempdir().unwrap();
        let e = install(
            dir.path(),
            Provider::Codex,
            Some(Scope::Local),
            "vibedeck",
            false,
            "v",
        )
        .unwrap_err();
        assert_eq!(e.to_string(), "Codex suporta os escopos project ou user.");
        let e = uninstall(dir.path(), Provider::Codex, Some(Scope::Local), "vibedeck").unwrap_err();
        assert_eq!(e.to_string(), "Codex suporta project ou user.");
    }
}
