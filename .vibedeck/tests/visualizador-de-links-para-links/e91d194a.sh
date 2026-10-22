#!/usr/bin/env bash
# Só http/https carregam no painel: checagem antes de load(URLRequest) e no decidePolicyFor do frame principal.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift|Tests/VibeDeckAppTests/LinkViewerTests\.swift'

nav=$(block '^enum LinkViewerNavigation')
need "$nav" '\["http", "https"\]\.contains\(url\.scheme\?\.lowercased\(\)' "permits(_:) deve aceitar só http/https"
need "$nav" 'guard permits\(url\) else \{ return \.cancel \}' "decision deve cancelar esquemas não http(s) no frame principal"

web=$(block 'struct LinkWebView: NSViewRepresentable')
upd=$(grep -A5 'func updateNSView' <<<"$web")
need "$upd" 'guard LinkViewerNavigation\.permits\(url\)' "updateNSView deve checar o esquema antes de load(URLRequest)"
lines=$(grep -n 'permits(url)\|view.load(URLRequest' <<<"$upd" | cut -d: -f1 | tr '\n' ' ')
read -r a b _ <<<"$lines"; [ -n "${b:-}" ] && [ "$a" -lt "$b" ] || bad "$F: checagem de esquema deve vir antes de view.load(URLRequest)"
need "$web" 'decidePolicyFor action: WKNavigationAction.*\n?' "Coordinator sem decidePolicyFor"
need "$(grep -A2 'decidePolicyFor action' <<<"$web")" 'LinkViewerNavigation\.decision\(' "decidePolicyFor deve usar LinkViewerNavigation.decision"

panel=$(block '^private struct LinkViewerPanel')
need "$panel" 'if let url = URL\(string: link\.url\), LinkViewerNavigation\.permits\(url\)' "painel deve checar o esquema antes de montar o WKWebView"
[ $fail -eq 0 ] || exit 1
run_tests unsupportedSchemesNeverLoadInMainFrameOrPopup
