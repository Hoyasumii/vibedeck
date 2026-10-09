#!/usr/bin/env bash
# O Descubra tem botão de cancelar e timeout, e descarta a resposta se o item mudou ou deixou de estar
# selecionado durante a chamada.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/CodexReadOnly\.swift$'
# Timeout.
need "$CORE" 'public static let timeout: Duration = \.seconds\([0-9]+\)' "ReviewDiscover.timeout não definido"
need "$APP" 'Task\.sleep\(for: ReviewDiscover\.timeout\)' "o processo do claude não respeita ReviewDiscover.timeout"
need "$APP" 'process\.terminate\(\)' "o timeout/cancelamento precisa encerrar o processo"
need "$APP" 'throw VibeDeckError\.discoverTimedOut' "timeout precisa virar erro discoverTimedOut"
if grep -q 'CodexReadOnly()' "$APP"; then
  grep 'CodexReadOnly().run(' "$APP" | grep -q 'timeout: ReviewDiscover.timeout' || { echo "$APP: chamada Codex sem timeout: ReviewDiscover.timeout"; fail=1; }
fi
# Cancelar.
need "$VIEW" 'Button\("Cancelar"\) \{ discover\.cancel\(\) \}' "o inspetor precisa de um botão Cancelar durante o Descubra"
need "$APP" 'onCancel: \{' "cancelar a Task precisa encerrar o processo (withTaskCancellationHandler)"
# Descarta a resposta após cancelamento.
[ "$(grep -c 'guard !Task.isCancelled else { return }' "$APP")" -ge 2 ] || { echo "$APP: a resposta/erro precisa ser descartado se a Task foi cancelada"; fail=1; }
# Item mudou / deixou de estar selecionado.
need "$VIEW" '\.onChange\(of: item\.updatedAt\) \{ discover\.itemChanged\(\) \}' "o inspetor precisa cancelar o Descubra quando o item muda"
need "$VIEW" '\.onDisappear \{ discover\.cancel\(\) \}' "o inspetor precisa cancelar o Descubra ao sair"
grep -A8 'ReviewItemInspector(' "$VIEW" | grep -q '\.id(item\.id)' || { echo "$VIEW: o inspetor precisa de .id(item.id) para ser recriado (e cancelar) ao trocar a seleção"; fail=1; }
ic=$(body "$APP" 'func itemChanged\(')
printf '%s\n' "$ic" | grep -q 'task?.cancel()' || { echo "$APP: itemChanged deve cancelar a Task"; fail=1; }
printf '%s\n' "$ic" | grep -q 'state = .failed(' || { echo "$APP: itemChanged deve avisar que a resposta foi descartada"; fail=1; }
finish
