#!/usr/bin/env bash
# Geração de testes valida os registros produzidos: ids pedidos mantêm o conteúdo da regra e têm teste válido (script ou manual).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
fail=0
bad() { echo "$1"; fail=1; }
G=Sources/VibeDeckApp/RuleTestGenerator.swift
grep -q 'static func validateGeneration' "$G" || bad "$G: validateGeneration ausente"
grep -q 'rule.contentHash == original.contentHash' "$G" || bad "$G: a validação deve comparar o conteúdo da regra (contentHash)"
grep -q 'rule.testState == .script || rule.testState == .manual' "$G" || bad "$G: a validação deve exigir teste registrado (script ou manual)"
grep -q 'for original in expected' "$G" || bad "$G: todos os ids solicitados devem ser validados"
[ "$(grep -c 'validateGeneration(' "$G")" -ge 3 ] || bad "$G: validateGeneration deve ser chamada nos fluxos de geração"
# Core Rust: set_rule_test grava o hash do conteúdo, para detectar regra alterada, e o runner valida o script registrado.
cargo_test -p vibedeck --test rules_mcp -- topics_and_rules_tools failed_must_script_reports_output
[ $fail -eq 0 ] || exit 1
