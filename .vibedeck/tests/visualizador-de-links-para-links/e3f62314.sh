#!/usr/bin/env bash
# Botão “Fechar” (LoggedButton, .help pt-BR) zera o link exibido e desmonta o WKWebView.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

panel=$(block '^private struct LinkViewerPanel')
need "$panel" 'LoggedButton\("Fechar", action: close\)' "painel deve ter LoggedButton(\"Fechar\", action: close)"
help=$(grep -A3 'LoggedButton("Fechar"' <<<"$panel" | grep -o '\.help("[^"]*")' || true)
[ -n "$help" ] || bad "$F: botão Fechar sem .help"
grep -Eq '\.help\("Fechar [^"]+"\)' <<<"$help" || bad "$F: .help do Fechar deve estar em pt-BR (\"Fechar …\"): $help"

lv=$(block '^struct LinksView: View')
need "$lv" 'LinkViewerPanel\(link: viewing\) \{ self\.viewing = nil \}' "fechar deve definir viewing = nil"
need "$lv" 'if let viewing \{' "painel só existe enquanto há link exibido (tabela volta à largura total)"

web=$(block 'struct LinkWebView: NSViewRepresentable')
dis=$(grep -A4 'static func dismantleNSView' <<<"$web" || true)
[ -n "$dis" ] || bad "$F: LinkWebView sem dismantleNSView"
need "$dis" 'stopLoading\(\)' "dismantleNSView deve parar o carregamento"
need "$dis" 'navigationDelegate = nil' "dismantleNSView deve soltar o navigationDelegate"
exit $fail
