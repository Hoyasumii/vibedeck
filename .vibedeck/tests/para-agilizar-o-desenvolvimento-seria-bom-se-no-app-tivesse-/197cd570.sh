#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# O prompt de "Implementar" vive no app (IdeaImplementation.prompt, Sources/VibeDeckApp/Core/Model/Rules.swift) e
# tem gêmeo no Core Rust (ideas::implementation_prompt). Exige teste do app com e sem tópico promovido.
T=Tests/VibeDeckAppTests
fail() { echo "$1" >&2; exit 1; }
if [ -n "${VIBEDECK_FILES:-}" ]; then
  printf '%s\n' "$VIBEDECK_FILES" | grep -E '^(Sources/VibeDeckApp/(IdeaView|Core/Model/Rules)\.swift|Tests/VibeDeckAppTests/.*|crates/vibedeck-core/src/ideas\.rs)$' >/dev/null || exit 77
fi
grep -q 'fn implementation_prompt(' crates/vibedeck-core/src/ideas.rs || fail "crates/vibedeck-core/src/ideas.rs: ideas::implementation_prompt sumiu"
grep -rq "IdeaImplementation.prompt" "$T" || fail "$T: nenhum teste de IdeaImplementation.prompt"
grep -rE "IdeaImplementation.prompt\(.*topic: nil" "$T" >/dev/null || fail "$T: falta caso com topic: nil"
grep -rE "IdeaImplementation.prompt\(.*topic: \"" "$T" >/dev/null || fail "$T: falta caso com topic não nil"
grep -rq "get_rule_topic" "$T" && grep -rq "regras rascunho" "$T" || fail "$T: os testes precisam checar a menção ao tópico e às regras rascunho"
exit 0
