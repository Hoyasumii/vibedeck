#!/usr/bin/env bash
# “Abrir no navegador” existe no menu de contexto e no painel e chama openURL.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

check() { # <texto> <onde>
  local b; b=$(grep -A2 'LoggedButton("Abrir no navegador")' <<<"$1" || true)
  [ -n "$b" ] || { bad "$F: $2 sem LoggedButton(\"Abrir no navegador\")"; return; }
  grep -q 'openURL(url)' <<<"$b" || bad "$F: \"Abrir no navegador\" ($2) deve chamar openURL"
}
menu=$(awk '/\.contextMenu\(forSelectionType: ProjectLink\.ID\.self\)/{f=1} f{print} /primaryAction:/{exit}' <<<"$(block '^struct LinksView: View')")
[ -n "$menu" ] || bad "$F: menu de contexto da tabela não encontrado"
check "$menu" "menu de contexto"
check "$(block '^private struct LinkViewerPanel')" "painel do visualizador"
exit $fail
