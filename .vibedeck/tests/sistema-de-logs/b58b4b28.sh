#!/usr/bin/env bash
# README e guide.md documentam ações/reações e a leitura por app, CLI e MCP (em pt-BR).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^README\.md$|^\.vibedeck/guide\.md$|^Sources/VibeDeckApp/|^Sources/vibedeck/'
fail=0
bad() { echo "$1"; fail=1; }
for f in README.md .vibedeck/guide.md; do
  [ -f "$f" ] || { bad "$f: ausente"; continue; }
  for term in 'ui\.\*' 'context\.action' 'context\.control' 'context\.label' 'store\.' 'Diagnóstico' 'vibedeck logs' '--level info' '--action'; do
    grep -qE -- "$term" "$f" || bad "$f: não menciona '${term//\\/}'"
  done
done
grep -q 'read_logs' .vibedeck/guide.md || bad ".vibedeck/guide.md: não menciona a ferramenta MCP read_logs"
grep -qE 'read_logs|vibedeck://logs' README.md || bad "README.md: não menciona leitura pelo MCP"
grep -q 'Id da ação' README.md || bad "README.md: não menciona o filtro 'Id da ação' do app"
[ $fail -eq 0 ] || exit 1
