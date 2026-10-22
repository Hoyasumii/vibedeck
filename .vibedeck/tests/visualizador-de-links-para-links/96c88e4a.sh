#!/usr/bin/env bash
# WKWebView do visualizador usa websiteDataStore não persistente.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

mk=$(awk '/func makeNSView\(context: Context\) -> WKWebView/{f=1} f{print} f&&/return view/{exit}' <<<"$(block 'struct LinkWebView: NSViewRepresentable')")
[ -n "$mk" ] || bad "$F: makeNSView do LinkWebView não encontrado"
need "$mk" 'config\.websiteDataStore = \.nonPersistent\(\)' "makeNSView deve usar config.websiteDataStore = .nonPersistent()"
need "$mk" 'WKWebView\(frame: \.zero, configuration: config\)' "WKWebView deve usar a configuração não persistente"
deny "$(block 'struct LinkWebView: NSViewRepresentable')" 'WKWebsiteDataStore\.default\(\)|websiteDataStore = \.default' "visualizador não pode usar o data store padrão"
exit $fail
