#!/usr/bin/env bash
# O visualizador não tem barra de endereço, campo de URL nem voltar/avançar.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

viewer="$(block '^private struct LinkViewerPanel')"$'\n'"$(block 'struct LinkWebView: NSViewRepresentable')"
[ -n "$(block '^private struct LinkViewerPanel')" ] || bad "$F: LinkViewerPanel não encontrado"
deny "$viewer" 'TextField|CommitTextField|\.searchable' "visualizador não deve ter campo de URL"
deny "$viewer" 'goBack|goForward|canGoBack|canGoForward|backForwardList|"Voltar"|"Avançar"' "visualizador não deve ter voltar/avançar"
exit $fail
