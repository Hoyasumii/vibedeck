#!/usr/bin/env bash
# Tópicos aplicáveis = globais (sem paths) + os que casam arquivos alterados + explícitos; o app mostra "Sem escopo".
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/|^Tests/VibeDeckCoreTests/RulesTests\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
grep -q 'public var isGlobal: Bool { paths.isEmpty }' Sources/VibeDeckCore/Rules.swift || bad "Sources/VibeDeckCore/Rules.swift: isGlobal deve ser paths.isEmpty"
grep -q 'entry.topic.isGlobal || named.contains(entry.slug) || relative.contains { entry.topic.matches(file: $0) }' Sources/VibeDeckCore/ProjectStore.swift \
  || bad "Sources/VibeDeckCore/ProjectStore.swift: applicableTopics deve ser globais + explícitos + os que casam os arquivos"
grep -q 'Sem escopo: vale para toda tarefa' Sources/VibeDeckApp/RulesView.swift || bad "Sources/VibeDeckApp/RulesView.swift: falta o aviso \"Sem escopo: vale para toda tarefa\""
[ $fail -eq 0 ] || exit 1
run_tests RulesTests/globs RulesTests/applicableTopics
