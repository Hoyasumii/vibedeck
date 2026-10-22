#!/usr/bin/env bash
# Tópicos aplicáveis = globais (sem paths) + os que casam arquivos alterados + explícitos; o app mostra "Sem escopo".
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^(crates|Sources)/'
fail=0
bad() { echo "$1"; fail=1; }
grep -q 'pub fn is_global(&self) -> bool' crates/vibedeck-core/src/model/rule_topic.rs && grep -A3 'pub fn is_global' crates/vibedeck-core/src/model/rule_topic.rs | grep -q 'self.paths.is_empty()' \
  || bad "crates/vibedeck-core/src/model/rule_topic.rs: is_global deve ser paths.is_empty()"
T=crates/vibedeck-core/src/rules/topics.rs
grep -q 'entry.value.is_global()' "$T" && grep -q 'named.contains(&entry.slug)' "$T" && grep -q 'relative.iter().any(|f| entry.value.matches_file(f))' "$T" \
  || bad "$T: applicable_topics deve ser globais + explícitos + os que casam os arquivos"
grep -q 'Sem escopo: vale para toda tarefa' Sources/VibeDeckApp/RulesView.swift || bad "Sources/VibeDeckApp/RulesView.swift: falta o aviso \"Sem escopo: vale para toda tarefa\""
grep -q 'var isGlobal: Bool { paths.isEmpty }' Sources/VibeDeckApp/Core/Model/Rules.swift || bad "Sources/VibeDeckApp/Core/Model/Rules.swift: isGlobal deve ser paths.isEmpty"
[ $fail -eq 0 ] || exit 1
cargo_tests vibedeck-core globs applicable_topics_by_scope
