//! Portão do hook `Stop`: o agente não encerra o turno enquanto um arquivo que ele alterou tem regras
//! aplicáveis sem check aprovado gravado depois da alteração (`StopGate.swift`).

use std::collections::HashSet;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::store::Store;

use super::error::Result;
use super::tasks::list_checks;
use super::topics::{applicable_topics, relative_path};

/// Um arquivo alterado cujas regras aplicáveis não têm check aprovado depois da alteração.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UnverifiedChange {
    pub file: String,
    pub topics: Vec<String>,
    /// O check mais novo que cobre os tópicos do arquivo depois da alteração falhou (em vez de não existir).
    pub last_check_failed: bool,
}

/// Arquivos que mudam como efeito colateral (checks, estado de runs, guia gerado, permissões).
const IGNORED: &[&str] = &[
    ".vibedeck/checks/",
    ".vibedeck/runs/",
    ".vibedeck/AGENTS.md",
    ".claude/settings.local.json",
    ".codex/hooks.json",
];

/// Roda `git` em `root`; `None` se não executa ou termina com erro (sem git o gate vê "nada alterado").
fn git(root: &Path, args: &[&str]) -> Option<Vec<u8>> {
    let out = Command::new("git")
        .args(args)
        .current_dir(root)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    out.status.success().then_some(out.stdout)
}

/// Arquivos alterados na árvore de trabalho (rastreados contra HEAD mais não rastreados), com a data de
/// modificação, só os modificados em `since` ou depois (`None` = desde sempre). Apagados não têm data.
pub fn working_tree_changes(root: &Path, since: Option<SystemTime>) -> Vec<(String, SystemTime)> {
    let tracked = git(root, &["diff", "--name-only", "--relative", "-z", "HEAD"]);
    let untracked = git(root, &["ls-files", "--others", "--exclude-standard", "-z"]);
    let mut paths: Vec<String> = [tracked, untracked]
        .into_iter()
        .flatten()
        .flat_map(|bytes| {
            bytes
                .split(|b| *b == 0)
                .filter(|p| !p.is_empty())
                .map(|p| String::from_utf8_lossy(p).into_owned())
                .collect::<Vec<_>>()
        })
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    paths.sort();
    paths
        .into_iter()
        .filter(|p| !IGNORED.iter().any(|prefix| p.starts_with(prefix)))
        .filter_map(|p| {
            let modified = std::fs::metadata(root.join(&p))
                .and_then(|m| m.modified())
                .ok()?;
            since.is_none_or(|s| modified >= s).then_some((p, modified))
        })
        .collect()
}

/// Arquivos alterados que ainda precisam de check aprovado: o check mais novo, gravado depois da alteração e
/// cobrindo todos os tópicos do arquivo, tem de ter passado. Arquivo sem regras aplicáveis é livre.
pub fn unverified_changes(
    store: &Store,
    changes: &[(String, SystemTime)],
) -> Result<Vec<UnverifiedChange>> {
    let checks = list_checks(store)?;
    let mut out = Vec::new();
    for (file, modified) in changes {
        let topics: Vec<String> = applicable_topics(store, std::slice::from_ref(file), &[])?
            .into_iter()
            .filter(|t| !t.value.rules.is_empty())
            .map(|t| t.slug)
            .collect();
        if topics.is_empty() {
            continue;
        }
        let modified: DateTime<Utc> = (*modified).into();
        // As datas dos checks são gravadas sem fração de segundo: tolera o segundo de que foram truncadas.
        let covering = checks.iter().find(|c| {
            c.created_at.0 + Duration::from_secs(1) >= modified
                && topics.iter().all(|t| c.topics.contains(t))
        });
        if covering.is_some_and(|c| c.passed) {
            continue;
        }
        out.push(UnverifiedChange {
            file: relative_path(store, file),
            topics,
            last_check_failed: covering.is_some(),
        });
    }
    Ok(out)
}

/// O motivo devolvido ao agente quando o gate bloqueia.
pub fn stop_gate_reason(unverified: &[UnverifiedChange]) -> String {
    let mut lines: Vec<String> = unverified
        .iter()
        .take(15)
        .map(|c| {
            format!(
                "- {} ({}){}",
                c.file,
                c.topics.join(", "),
                if c.last_check_failed {
                    " — o último check falhou"
                } else {
                    ""
                }
            )
        })
        .collect();
    if unverified.len() > 15 {
        lines.push(format!("- … e mais {}", unverified.len() - 15));
    }
    format!(
        "VibeDeck: a tarefa não pode ser concluída sem um check de regras aprovado depois das alterações. Arquivos alterados sem check:\n{}\nChame `rules_for` (ou `vibedeck rules for <arquivos> --json`) com esses arquivos e envie `submit_rule_check` (ou `vibedeck rules check`) sem `results`: ele roda os scripts. Regras manuais só se o usuário pedir. Se falhar, corrija e envie de novo.",
        lines.join("\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reason_lists_files_and_truncates() {
        let one = vec![UnverifiedChange {
            file: "a.rs".into(),
            topics: vec!["geral".into(), "core".into()],
            last_check_failed: true,
        }];
        let r = stop_gate_reason(&one);
        assert!(r.contains("Arquivos alterados sem check:\n- a.rs (geral, core) — o último check falhou\nChame `rules_for`"));
        assert!(r.starts_with("VibeDeck: a tarefa não pode ser concluída"));
        let many: Vec<_> = (0..20)
            .map(|i| UnverifiedChange {
                file: format!("f{i}"),
                topics: vec!["t".into()],
                last_check_failed: false,
            })
            .collect();
        let r = stop_gate_reason(&many);
        assert!(r.contains("- f14 (t)\n- … e mais 5\nChame"));
        assert!(!r.contains("f15"));
    }
}
