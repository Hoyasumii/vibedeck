#!/usr/bin/env bash
# Subrecursos, iframes e redirecionamento inicial do frame principal são permitidos.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift|Tests/VibeDeckAppTests/LinkViewerTests\.swift'

nav=$(block '^enum LinkViewerNavigation')
need "$nav" 'if isMainFrame == false \{ return \.allow \}' "decision deve permitir navegações de subframes"
dec=$(awk '/static func decision/{f=1} f{print}' <<<"$nav")
last=$(grep -E 'return ' <<<"$dec" | tail -1)
grep -q 'return .allow' <<<"$last" || bad "$F: decision deve terminar permitindo o que não é .linkActivated/.formSubmitted (achou: $last)"
web=$(block 'struct LinkWebView: NSViewRepresentable')
need "$web" 'case \.allow: return \.allow' "decidePolicyFor deve repassar .allow"
[ $fail -eq 0 ] || exit 1
# Redirecionamento http→https (sem rede): teste unitário com a mesma decisão do WKWebView.
run_tests initialRequestAndRedirectStayEmbedded subframesRemainAvailableAndMissingURLIsRejected
