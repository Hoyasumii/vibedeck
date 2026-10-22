#!/usr/bin/env bash
# Fechar/Abrir no navegador usam LoggedButton + loggedControl("links_view.…") estável, sem URL no log.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

panel=$(block '^private struct LinkViewerPanel')
menu=$(awk '/\.contextMenu\(forSelectionType/{f=1} f{print} /primaryAction:/{exit}' <<<"$(block '^struct LinksView: View')")
for lbl in Fechar "Abrir no navegador"; do
  b=$(grep -A3 "LoggedButton(\"$lbl\"" <<<"$panel" || true)
  [ -n "$b" ] || { bad "$F: painel sem LoggedButton(\"$lbl\")"; continue; }
  grep -Eq "\.loggedControl\(control: \"links_view\.[a-z0-9_]+\", label: \"$lbl\"\)" <<<"$b" \
    || bad "$F: \"$lbl\" no painel precisa de loggedControl(control: \"links_view.…\", label: \"$lbl\")"
done
b=$(grep -A3 'LoggedButton("Abrir no navegador"' <<<"$menu" || true)
grep -Eq '\.loggedControl\(control: "links_view\.[a-z0-9_]+", label: "Abrir no navegador"\)' <<<"$b" \
  || bad "$F: \"Abrir no navegador\" do menu precisa de loggedControl(control: \"links_view.…\")"
ids=$(grep -Eo 'control: "links_view\.(viewer_[a-z0-9_]+|open_in_browser)"' <<<"$panel"$'\n'"$menu" | sort)
[ -z "$(uniq -d <<<"$ids")" ] || bad "$F: identificadores repetidos: $(uniq -d <<<"$ids")"
# Só os argumentos passados ao log (loggedControl/VDLog/logging) importam.
logs=$(grep -Eo '(loggedControl|VDLog\.[a-zA-Z]+|logging)\([^)]*\)' <<<"$panel"$'\n'"$menu"$'\n'"$(block 'struct LinkWebView: NSViewRepresentable')" || true)
deny "$logs" '\\\(|link\.url|context:|: *url\b|\.absoluteString' "log não pode guardar a URL nem usar identificador interpolado"
exit $fail
