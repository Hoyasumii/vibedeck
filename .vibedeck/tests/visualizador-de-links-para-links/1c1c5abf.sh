#!/usr/bin/env bash
# Abrir (duplo clique/“Abrir”) mostra a URL num WKWebView embutido ao lado da tabela, sem navegador externo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

open=$(block 'private func open[(]_ link: ProjectLink[)]')
[ -n "$open" ] || bad "$F: open(_:) não encontrado"
deny "$open" 'openURL|NSWorkspace' "open(_:) não pode abrir o navegador externo"
need "$open" 'viewing = link' "open(_:) deve definir o link exibido (viewing = link)"

lv=$(block '^struct LinksView: View')
need "$lv" 'LoggedButton\("Abrir"\) \{ open\(link\) \}' "menu de contexto “Abrir” deve chamar open(link)"
need "$lv" 'primaryAction: \{ ids in' "Table sem primaryAction (duplo clique)"
need "$lv" '\.forEach\(open\)' "primaryAction deve chamar open"
need "$lv" 'HSplitView' "painel deve ficar ao lado da tabela (HSplitView)"
need "$lv" 'if let viewing \{' "painel deve depender do link exibido"
need "$lv" 'LinkViewerPanel\(link: viewing\)' "LinksView deve montar LinkViewerPanel com o link exibido"

panel=$(block '^private struct LinkViewerPanel')
need "$panel" 'LinkWebView\(url: url' "LinkViewerPanel deve embutir LinkWebView"
web=$(block 'struct LinkWebView: NSViewRepresentable')
need "$web" 'func makeNSView\(context: Context\) -> WKWebView' "LinkWebView deve criar um WKWebView"
exit $fail
