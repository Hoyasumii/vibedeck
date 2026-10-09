#!/usr/bin/env bash
# must em fail → passed=false (bloqueia done); should em fail → passed=true com aviso ao usuário.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/|^Sources/vibedeck/|^Tests/VibeDeckCoreTests/RulesTests\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
S=Sources/VibeDeckCore/ProjectStore.swift
grep -q 'passed: !failed.contains { $0.1.severity == .must }' "$S" || bad "$S: passed deve ser 'nenhum must em fail'"
grep -q 'warnings: failed.filter { $0.1.severity == .should }' "$S" || bad "$S: should em fail deve virar warning"
grep -q 'failures: failed.filter { $0.1.severity == .must }' "$S" || bad "$S: must em fail deve virar failure"
# Item só vai para done com o último check aprovado.
grep -A10 'func verificationProblems' "$S" | grep -q 'if !check.passed' || bad "$S: verificationProblems não bloqueia check reprovado"
M=Sources/vibedeck/MCPServer.swift
# The agent-facing summary lives in RuleCheck.agentSummary (Core); the MCP returns it.
O=Sources/VibeDeckCore/RuleAgentOutput.swift
grep -A20 'case "submit_rule_check":' "$M" | grep -q 'agentSummary' || bad "$M: submit_rule_check não devolve RuleCheck.agentSummary"
grep -A12 'func agentSummary' "$O" | grep -q 'Check reprovado' || bad "$O: submit_rule_check não diz que o check foi reprovado"
grep -A12 'func agentSummary' "$O" | grep -q 'avise o usuário' || bad "$O: submit_rule_check não pede para avisar o usuário dos should"
C=Sources/vibedeck/CLI.swift
grep -q 'for w in check.warnings' "$C" || bad "$C: rules check não mostra os avisos (should)"
grep -q 'if !check.passed { throw ExitCode.failure }' "$C" || bad "$C: rules check não falha quando passed=false"
grep -q 'case "update_review_item":' "$M" && { grep -A6 'case "update_review_item":' "$M" | grep -q 'ensureVerified' || bad "$M: update_review_item não exige check aprovado para done"; }
[ $fail -eq 0 ] || exit 1
run_tests RulesTests/submitCheck RulesTests/reviewItemGate
