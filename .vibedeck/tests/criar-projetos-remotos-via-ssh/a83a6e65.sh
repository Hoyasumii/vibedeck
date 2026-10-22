#!/usr/bin/env bash
# A83A6E65: reconexão automática com intervalo crescente, botão Reconectar; senha só com interação do usuário.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $SHEET 'func synchronize\(force')
for p in 'guard force \|\| Date\(\) >= nextAttempt' 'delay = min\(60, delay \* 2\)' 'nextAttempt = Date\(\)\.addingTimeInterval\(delay\)' 'error = nil; delay = 2'; do
  grep -qE -- "$p" <<<"$B" || { echo "$SHEET (synchronize): falta '$p' (nova tentativa com intervalo crescente)"; fail=1; }
done
in_body $SHEET '^struct RemoteProjectBar' 'while !Task\.isCancelled' "as tentativas automáticas devem rodar enquanto o projeto está aberto"
needF $SHEET 'LoggedButton("Reconectar") { Task { await status.synchronize(force: true) } }' "falta o botão Reconectar"
needF $SHEET 'LoggedButton("Senha…") { status.credentials = true }' "o pedido de senha deve ser uma ação do usuário"
in_body $CONN 'public func connect\(' 'else \{ args \+= \["-o", "BatchMode=yes"\] \}' "reconexão automática sem senha não pode abrir prompt"
finish
