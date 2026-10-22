#!/usr/bin/env bash
# .linkActivated no frame principal para outra URL e window.open/_blank abrem no navegador padrão, não no painel.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift|Tests/VibeDeckAppTests/LinkViewerTests\.swift'

nav=$(block '^enum LinkViewerNavigation')
need "$nav" 'type == \.linkActivated && url != currentURL\) \{ return \.external \}' "decision deve mandar .linkActivated para outra URL ao navegador"
need "$nav" 'if opensWindow \|\| isMainFrame == nil \{' "decision deve tratar window.open/target=_blank"

web=$(block 'struct LinkWebView: NSViewRepresentable')
pol=$(awk '/decidePolicyFor action/{f=1} f{print} f&&/^        }$/{exit}' <<<"$(sed 's/^[^:]*:[0-9]*: //' <<<"$web")")
need "$pol" 'case \.external:' "decidePolicyFor sem caso .external"
ext=$(awk '/case \.external:/{f=1} f{print}' <<<"$pol")
need "$ext" 'NSWorkspace\.shared\.open\(url\)' "caso .external deve chamar NSWorkspace.shared.open"
need "$ext" 'return \.cancel' "caso .external deve retornar .cancel"

cw=$(awk '/createWebViewWith configuration/{f=1} f{print} f&&/^        }$/{exit}' <<<"$(sed 's/^[^:]*:[0-9]*: //' <<<"$web")")
[ -n "$cw" ] || bad "$F: Coordinator sem createWebViewWith"
need "$cw" 'opensWindow: true' "createWebViewWith deve decidir com opensWindow: true"
need "$cw" 'NSWorkspace\.shared\.open\(url\)' "createWebViewWith deve abrir a URL no navegador"
rets=$(grep -Eo 'return [^ ]+' <<<"$cw" | sort -u)
[ "$rets" = "return nil" ] || bad "$F: createWebViewWith deve retornar sempre nil (achou: $rets)"
[ $fail -eq 0 ] || exit 1
run_tests otherPagesAndFormsOpenExternally
