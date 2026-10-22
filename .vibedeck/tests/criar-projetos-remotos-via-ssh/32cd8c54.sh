#!/usr/bin/env bash
# 32CD8C54: estados distintos (desconectado, sincronizando, pendente, conflito, sincronizado); "Sincronizado" só sem pendências/conflitos.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $SHEET '^final class RemoteProjectStatus')
for s in '"Desconectado"' '"Sincronizando…"' '"Alterações pendentes"' '"Conflito"' '"Sincronizado"' '"Desconectado · '; do
  grep -qF -- "$s" <<<"$B" || { echo "$SHEET: falta o estado $s"; fail=1; }
done
while IFS= read -r l; do
  grep -q 'pendingCount == 0' <<<"$l" && grep -q 'conflicts.isEmpty' <<<"$l" || { echo "$SHEET: 'Sincronizado' sem checar pendências e conflitos: $l"; fail=1; }
done < <(grep -F '"Sincronizado"' $SHEET)
needF $SHEET 'Label(status.message, systemImage: status.busy ?' "o estado deve ser exibido no projeto"
needF $SHEET 'if status.pending > 0 { Text("\(status.pending) alteração(ões) pendente(s)")' "o número de pendências deve ser exibido"
finish
