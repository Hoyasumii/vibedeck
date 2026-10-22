#!/usr/bin/env bash
# Recuperação limitada, mesmo modelo/provedor, só para resposta inválida de função sem escrita; transporte/cancelamento não repetem.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
fail=0
bad() { echo "$1"; fail=1; }
# App (AIReadOnlyOperation): uma única recuperação, sem repetir erro de transporte nem cancelamento.
A=Sources/VibeDeckApp/AIReadOnlyOperation.swift
grep -q 'guard recover(error) else { throw error }' "$A" || bad "$A: só respostas inválidas aceitas por recover() podem ser recuperadas"
grep -q 'guard attempt == 1 else' "$A" || bad "$A: a recuperação deve ser limitada a uma tentativa"
grep -q 'AIPromptPolicy.recovery(prompt' "$A" || bad "$A: a recuperação deve reutilizar o prompt original"
grep -qE 'catch is CancellationError' "$A" || bad "$A: cancelamento não pode virar recuperação"
grep -qE 'fallback|downgrade' "$A" && bad "$A: recuperação não pode trocar modelo ou provedor"
grep -q 'func invalidAnswerGetsOneRecoveryWithoutChangingSettings' Tests/VibeDeckAppTests/AIRecoveryTests.swift || bad "AIRecoveryTests: teste da recuperação única ausente"
grep -q 'func persistentFailureStopsAndTransportErrorsDoNotRetry' Tests/VibeDeckAppTests/AIRecoveryTests.swift || bad "AIRecoveryTests: teste de falha persistente/transporte ausente"
# Core Rust: o texto de recuperação e a mensagem final existem, e nada no Core repete chamadas de IA em laço.
C=crates/vibedeck-core/src/ai/context.rs
grep -q 'pub fn recovery' "$C" && grep -q 'pub const INCOMPLETE' "$C" || bad "$C: recovery()/INCOMPLETE ausentes"
grep -q 'fn politica_aparece_no_prompt' "$C" || bad "$C: teste da recuperação única ausente"
grep -rnE --include='*.rs' 'retry|retries|for attempt in' crates/vibedeck-core/src/ai crates/vibedeck/src/mcp/tools/ai.rs && bad "Core Rust: repetição automática de chamada de IA encontrada"
[ $fail -eq 0 ] || exit 1
cargo_test -p vibedeck-core --lib -- ai::context::tests::politica_aparece_no_prompt
