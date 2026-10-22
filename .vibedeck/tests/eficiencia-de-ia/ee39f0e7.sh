#!/usr/bin/env bash
# Política cobre todos os provedores; sem troca/rebaixamento automático de modelo; limitações reportadas.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
fail=0
for f in "$POLICY" "$APP_POLICY"; do
  for p in 'Não troque modelo nem provedor automaticamente' 'informe' 'sugira um modelo mais capaz'; do
    grep -qF "$p" "$f" || { echo "$f: cláusula ausente: $p"; fail=1; }
  done
done
if grep -rnE 'fallback-model|fallbackModel|downgrade' Sources crates --include=*.swift --include=*.rs; then
  echo "Troca/rebaixamento automático de modelo encontrado"; fail=1
fi
grep -q 'incomplete' Sources/VibeDeckApp/AIReadOnlyOperation.swift || { echo "AIReadOnlyOperation não reporta limitação (incomplete)"; fail=1; }
grep -q 'pub const INCOMPLETE' crates/vibedeck-core/src/ai/context.rs || { echo "ai/context.rs: mensagem de limitação (INCOMPLETE) ausente"; fail=1; }
# Cada provedor do Core Rust (Claude e Codex) injeta a política compartilhada.
for g in crates/vibedeck-core/src/ai/process.rs crates/vibedeck-core/src/ai/codex.rs Sources/VibeDeckApp/Core/AI/CodexReadOnly.swift Sources/VibeDeckApp/Core/AI/ClaudeStream.swift; do
  grep -qE 'context::INSTRUCTIONS|AIPromptPolicy' "$g" || { echo "$g: provedor sem política compartilhada"; fail=1; }
done
exit $fail
