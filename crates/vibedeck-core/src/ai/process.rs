//! Processo `claude` somente leitura, compartilhado por app, CLI e MCP (AIReadOnlyProcess.swift): só
//! Read/Grep/Glob, prompt por stdin e prazo.

use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::channel;
use std::time::{Duration, Instant};

use super::codex::timeout_override;
use super::{AiError, Result, context, provider};
use crate::model::ProviderSettings;

pub const TOOLS: [&str; 3] = ["Read", "Grep", "Glob"];

/// Prazo da descoberta (180 s no Swift).
pub const DISCOVER_TIMEOUT: Duration = Duration::from_secs(180);

/// Argumentos de `claude -p` (o prompt vai no stdin: o `--tools` variádico engoliria um posicional final).
/// `--strict-mcp-config` sem configuração deixa de fora todo servidor MCP, o do próprio projeto inclusive.
pub fn arguments(schema: &str, settings: &ProviderSettings) -> Vec<String> {
    let tools = TOOLS.join(",");
    let mut args: Vec<String> = [
        "-p",
        "--output-format",
        "json",
        "--json-schema",
        schema,
        "--tools",
        &tools,
        "--allowedTools",
        &tools,
        "--strict-mcp-config",
        "--no-session-persistence",
        "--append-system-prompt",
        context::INSTRUCTIONS,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    if let Some(model) = &settings.model {
        args.extend(["--model".into(), model.clone()]);
    }
    if let Some(effort) = &settings.effort {
        args.extend(["--effort".into(), effort.clone()]);
    }
    args
}

/// Roda `exe` em `root` com `input` no stdin e devolve o stdout. Estourar o prazo mata o processo (e os
/// filhos dele, que ficam no mesmo grupo).
pub fn run_claude_read_only(
    exe: &Path,
    root: &Path,
    input: &str,
    schema: &str,
    settings: &ProviderSettings,
    timeout: Duration,
) -> Result<Vec<u8>> {
    let timeout = timeout_override().unwrap_or(timeout);
    let mut child = Command::new(exe)
        .args(arguments(schema, settings))
        .current_dir(root)
        .env("PATH", provider::child_path())
        .process_group(0)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AiError::DiscoverFailed(e.to_string()))?;
    let mut stdin = child.stdin.take();
    let input = input.as_bytes().to_vec();
    std::thread::spawn(move || {
        if let Some(mut s) = stdin.take() {
            let _ = s.write_all(&input);
        }
    });
    let mut stdout = child.stdout.take();
    let mut stderr = child.stderr.take();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(s) = stdout.as_mut() {
            let _ = s.read_to_end(&mut buf);
        }
        let _ = tx.send(buf);
    });
    // Drena o stderr em paralelo: um hook falante não pode encher o pipe e travar o processo.
    std::thread::spawn(move || {
        let mut sink = Vec::new();
        if let Some(s) = stderr.as_mut() {
            let _ = s.read_to_end(&mut sink);
        }
    });
    let deadline = Instant::now() + timeout;
    let mut timed_out = false;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if Instant::now() >= deadline {
                    timed_out = true;
                    // SAFETY: `killpg` só envia um sinal ao grupo criado acima.
                    unsafe { libc::killpg(child.id() as i32, libc::SIGKILL) };
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
                std::thread::sleep(Duration::from_millis(15));
            }
            Err(e) => return Err(AiError::DiscoverFailed(e.to_string())),
        }
    }
    if timed_out {
        return Err(AiError::DiscoverTimedOut);
    }
    // Um neto que herdou o pipe não pode segurar a resposta para sempre.
    Ok(rx.recv_timeout(Duration::from_secs(5)).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn argumentos_somente_leitura() {
        let args = arguments(
            "{}",
            &ProviderSettings {
                model: Some("m".into()),
                effort: Some("high".into()),
            },
        );
        assert_eq!(args[0], "-p");
        let tools = args.iter().position(|a| a == "--tools").unwrap();
        assert_eq!(args[tools + 1], "Read,Grep,Glob");
        assert!(args.contains(&"--strict-mcp-config".to_string()));
        assert!(args.windows(2).any(|w| w == ["--model", "m"]));
        assert!(args.windows(2).any(|w| w == ["--effort", "high"]));
        assert!(!arguments("{}", &ProviderSettings::default()).contains(&"--model".to_string()));
    }
}
