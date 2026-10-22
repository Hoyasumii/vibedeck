//! Providers `claude` e `codex` e detecção dos executáveis locais (AIProvider.swift, ClaudeCode.swift).

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::{Deserialize, Serialize};

use super::home_dir;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Claude,
    Codex,
}

impl Provider {
    pub fn parse(s: &str) -> Option<Provider> {
        match s {
            "claude" => Some(Provider::Claude),
            "codex" => Some(Provider::Codex),
            _ => None,
        }
    }

    pub fn raw(self) -> &'static str {
        match self {
            Provider::Claude => "claude",
            Provider::Codex => "codex",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Provider::Claude => "Claude",
            Provider::Codex => "Codex",
        }
    }

    /// Variável que substitui a detecção (testes e instalações atípicas).
    pub fn env_override(self) -> &'static str {
        match self {
            Provider::Claude => "VIBEDECK_CLAUDE_BIN",
            Provider::Codex => "VIBEDECK_CODEX_BIN",
        }
    }

    pub fn executable(self) -> Option<PathBuf> {
        locate(self)
    }
}

/// Pastas onde os instaladores colocam `claude`: PATH + `~/.local/bin`, `~/.claude/local`, Homebrew.
pub fn candidate_directories(home: &Path, path: Option<&str>) -> Vec<String> {
    let mut dirs: Vec<String> = path
        .unwrap_or("")
        .split(':')
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();
    for extra in [
        home.join(".local/bin"),
        home.join(".claude/local"),
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
    ] {
        dirs.push(extra.to_string_lossy().into_owned());
    }
    let mut seen = std::collections::HashSet::new();
    dirs.retain(|d| !d.is_empty() && seen.insert(d.clone()));
    dirs
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// Localiza o executável do provider: variável de override, pastas candidatas, depois o shell de login.
pub fn locate(provider: Provider) -> Option<PathBuf> {
    if let Some(custom) = std::env::var_os(provider.env_override()).filter(|v| !v.is_empty()) {
        let path = PathBuf::from(custom);
        return is_executable(&path).then_some(path);
    }
    let home = home_dir();
    let env_path = std::env::var("PATH").ok();
    let mut dirs = candidate_directories(&home, env_path.as_deref());
    if provider == Provider::Codex {
        dirs.push(home.join(".npm-global/bin").to_string_lossy().into_owned());
        dirs.push(home.join(".cargo/bin").to_string_lossy().into_owned());
    }
    for dir in dirs {
        let candidate = Path::new(&dir).join(provider.raw());
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    let found = login_shell(&format!("command -v {}", provider.raw()))?;
    let found = found.trim();
    let path = PathBuf::from(found);
    (found.starts_with('/') && is_executable(&path)).then_some(path)
}

fn default_shell() -> &'static str {
    if cfg!(target_os = "macos") {
        "/bin/zsh"
    } else {
        "/bin/sh"
    }
}

/// Roda `command` no shell de login do usuário e devolve o stdout (ou `None` se falhar).
pub fn login_shell(command: &str) -> Option<String> {
    let shell = std::env::var("SHELL")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| default_shell().to_string());
    let out = Command::new(shell)
        .arg("-lc")
        .arg(command)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() || out.stdout.is_empty() {
        return None;
    }
    String::from_utf8(out.stdout).ok()
}

/// PATH dos processos filhos: o do shell de login (para `git`, `node`, `vibedeck` como no terminal), com as
/// pastas candidatas como reserva.
pub fn child_path() -> String {
    let base = login_shell(r#"printf %s "$PATH""#).or_else(|| std::env::var("PATH").ok());
    candidate_directories(&home_dir(), base.as_deref()).join(":")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn candidatas_sem_duplicatas() {
        let dirs = candidate_directories(Path::new("/h"), Some("/a:/usr/local/bin:/a::"));
        assert_eq!(dirs[0], "/a");
        assert_eq!(dirs.iter().filter(|d| *d == "/usr/local/bin").count(), 1);
        assert!(dirs.contains(&"/h/.local/bin".to_string()));
        assert!(dirs.contains(&"/h/.claude/local".to_string()));
    }

    #[test]
    fn parse_e_titulos() {
        assert_eq!(Provider::parse("codex"), Some(Provider::Codex));
        assert_eq!(Provider::parse("x"), None);
        assert_eq!(Provider::Claude.title(), "Claude");
    }
}
