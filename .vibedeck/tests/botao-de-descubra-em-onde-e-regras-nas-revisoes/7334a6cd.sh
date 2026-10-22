#!/usr/bin/env bash
set -euo pipefail
# O Descubra tem botão de cancelar e timeout, e descarta a resposta se o item mudou ou deixou de estar
# selecionado durante a chamada.
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/Core/AI/CodexReadOnly\.swift$'
# Timeout.
need "$CORE" 'static let timeout: Duration = \.seconds\([0-9]+\)' "ReviewDiscover.timeout não definido"
need "$RS" 'pub const TIMEOUT_SECS: u64 = [0-9]+;' "TIMEOUT_SECS (Core Rust) não definido"
need "$PROC" 'Task\.sleep\(for: ReviewDiscover\.timeout\)' "o processo do claude não respeita ReviewDiscover.timeout"
need "$PROC" 'process\.terminate\(\)' "o timeout/cancelamento precisa encerrar o processo"
need "$PROC" 'throw VibeDeckError\.discoverTimedOut' "timeout precisa virar erro discoverTimedOut"
need "$OPERATION" 'timeout: \.seconds\(180\)' "a chamada Codex do Descubra precisa de timeout"
# Cancelar.
need "$VIEW" 'LoggedButton\("Cancelar"\) \{ discover\.cancel\(\) \}' "o inspetor precisa de um botão Cancelar durante o Descubra"
need "$PROC" 'onCancel: \{' "cancelar a Task precisa encerrar o processo (withTaskCancellationHandler)"
# Descarta a resposta após cancelamento.
[ "$(grep -c 'guard !Task.isCancelled else { return }' "$APP")" -ge 2 ] || { echo "$APP: a resposta/erro precisa ser descartado se a Task foi cancelada"; fail=1; }
# Item mudou / deixou de estar selecionado.
need "$VIEW" '\.onChange\(of: item\.updatedAt\) \{ discover\.itemChanged\(\) \}' "o inspetor precisa cancelar o Descubra quando o item muda"
need "$VIEW" '\.onDisappear \{ discover\.cancel\(\) \}' "o inspetor precisa cancelar o Descubra ao sair"
grep -A8 'ReviewItemInspector(' "$VIEW" | grep '\.id(item\.id)' >/dev/null || { echo "$VIEW: o inspetor precisa de .id(item.id) para ser recriado (e cancelar) ao trocar a seleção"; fail=1; }
ic=$(body "$APP" 'func itemChanged\(')
printf '%s\n' "$ic" | grep 'task?.cancel()' >/dev/null || { echo "$APP: itemChanged deve cancelar a Task"; fail=1; }
printf '%s\n' "$ic" | grep 'state = .failed(' >/dev/null || { echo "$APP: itemChanged deve avisar que a resposta foi descartada"; fail=1; }
finish
