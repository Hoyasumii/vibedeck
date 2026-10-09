#!/usr/bin/env bash
# Superfícies de IA (CLI Claude, Codex, chat, workflow, guia AGENTS) devem usar AIPromptPolicy.instructions.
set -euo pipefail
fail=0
need() { # arquivo, mínimo de ocorrências
    local n; n=$(grep -c 'AIPromptPolicy\.instructions' "$1" || true)
    if (( n < $2 )); then echo "$1: esperado ≥$2 uso(s) de AIPromptPolicy.instructions, encontrado $n"; fail=1; fi
}
need Sources/VibeDeckCore/ClaudeStream.swift 2
need Sources/VibeDeckCore/ReviewDiscover.swift 1
need Sources/VibeDeckCore/CodexReadOnly.swift 1
need Sources/VibeDeckCore/WorkflowRuns.swift 1
need Sources/VibeDeckCore/AgentsGuide.swift 1
need Sources/VibeDeckApp/ClaudeSession.swift 1
# Fonte única: o texto da política não pode ser duplicado fora de AIPromptPolicy.swift.
if grep -rn 'Não dispense validações obrigatórias' Sources --include=*.swift | grep -v 'AIPromptPolicy.swift'; then
    echo "Texto da política duplicado fora de AIPromptPolicy.swift"; fail=1
fi
exit $fail
