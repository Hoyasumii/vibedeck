#!/usr/bin/env bash
# Superfícies de IA (claude -p, Codex, workflows, kits, guia AGENTS; no app: chat, descoberta) usam a política compartilhada.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
fail=0
need() { # arquivo, padrão, mínimo de ocorrências
  local n; n=$(grep -c -E "$2" "$1" || true)
  if (( n < $3 )); then echo "$1: esperado ≥$3 uso(s) de $2, encontrado $n"; fail=1; fi
}
# Core Rust: fonte única ai/policy_instructions.txt (context::INSTRUCTIONS).
need crates/vibedeck-core/src/ai/process.rs 'context::INSTRUCTIONS' 1
need crates/vibedeck-core/src/ai/codex.rs 'context::INSTRUCTIONS' 1
need crates/vibedeck-core/src/ai/guide.rs 'context::INSTRUCTIONS' 1
need crates/vibedeck-core/src/workflows/prompts.rs 'POLICY' 1
need crates/vibedeck-core/src/resources/kits.rs 'POLICY' 1
need crates/vibedeck-core/src/reviews/discover.rs 'prompt_policy' 1
# As cópias do texto (include_str!) não podem divergir da fonte.
for copy in crates/vibedeck-core/src/workflows/policy.txt crates/vibedeck-core/assets/kits/policy.txt; do
  cmp -s "$POLICY" "$copy" || { echo "$copy: texto da política divergiu de $POLICY"; fail=1; }
done
if grep -rn --include='*.rs' 'Não dispense validações obrigatórias' crates; then
  echo "Texto da política duplicado em código Rust (use ai::context::INSTRUCTIONS)"; fail=1
fi
# App: AIPromptPolicy.instructions.
need Sources/VibeDeckApp/Core/AI/ClaudeStream.swift 'AIPromptPolicy\.instructions' 2
need Sources/VibeDeckApp/Core/Discover/ReviewDiscoverLogic.swift 'AIPromptPolicy\.instructions' 1
need Sources/VibeDeckApp/Core/AI/CodexReadOnly.swift 'AIPromptPolicy\.instructions' 1
need Sources/VibeDeckApp/Core/Model/WorkflowRuns.swift 'AIPromptPolicy\.instructions' 1
need Sources/VibeDeckApp/Core/Model/AgentsGuide.swift 'AIPromptPolicy\.instructions' 1
need Sources/VibeDeckApp/ClaudeSession.swift 'AIPromptPolicy\.instructions' 1
if grep -rn 'Não dispense validações obrigatórias' Sources --include=*.swift | grep -v 'AIPromptPolicy.swift'; then
  echo "Texto da política duplicado fora de AIPromptPolicy.swift"; fail=1
fi
exit $fail
