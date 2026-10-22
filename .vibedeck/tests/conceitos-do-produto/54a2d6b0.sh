#!/usr/bin/env bash
# must em fail → passed=false (bloqueia done); should em fail → passed=true com aviso ao usuário.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/'
fail=0
bad() { echo "$1"; fail=1; }
T=crates/vibedeck-core/src/rules/tasks.rs
grep -q 'passed: failures.is_empty()' "$T" || bad "$T: passed deve ser 'nenhum must em fail'"
grep -q 'r.severity == RuleSeverity::Should' "$T" || bad "$T: should em fail deve virar warning"
grep -q 'r.severity == RuleSeverity::Must' "$T" || bad "$T: must em fail deve virar failure"
# Item só vai para done com o último check aprovado.
grep -A25 'pub fn verification_problems' "$T" | grep 'if !check.passed' >/dev/null || bad "$T: verification_problems não bloqueia check reprovado"
# O resumo para o agente vive em rules::checklist::agent_summary (Core); o MCP devolve esse resumo.
O=crates/vibedeck-core/src/rules/checklist.rs
M=crates/vibedeck/src/mcp/tools/rules.rs
grep -A40 'fn submit_rule_check' "$M" | grep 'rules::agent_summary' >/dev/null || bad "$M: submit_rule_check não devolve agent_summary"
grep -A12 'pub fn agent_summary' "$O" | grep 'Check reprovado' >/dev/null || bad "$O: o resumo não diz que o check foi reprovado"
grep -A30 'pub fn agent_summary' "$O" | grep 'avise o usuário' >/dev/null || bad "$O: o resumo não pede para avisar o usuário dos should"
C=crates/vibedeck/src/cli/rules.rs
grep -q 'for w in &check.warnings' "$C" || bad "$C: rules check não mostra os avisos (should)"
grep -q 'Ok(i32::from(!check.passed))' "$C" || bad "$C: rules check não falha quando passed=false"
grep -q 'gate::ensure_verified' crates/vibedeck-core/src/reviews/mod.rs || bad "crates/vibedeck-core/src/reviews/mod.rs: update de item para done não exige check aprovado (ensure_verified)"
[ $fail -eq 0 ] || exit 1
cargo_tests vibedeck check_runs_scripts_and_records failed_must_script_reports_output
cargo_tests vibedeck-core gate_regra_nova_e_manual_must gate_regras_explicitas_do_item
