#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
others=$(grep -rl 'ruleScriptConcurrency' Sources schema vibedeck.json .vibedeck --include='*.swift' --include='*.json' 2>/dev/null | grep -v '^Sources/VibeDeckApp/' || true)
[ -z "$others" ] || { echo "a chave ruleScriptConcurrency só pode existir em Sources/VibeDeckApp; achei em: $others"; bad=1; }
grep -rq 'ruleScriptConcurrency' Sources/VibeDeckApp || { echo "chave do limite não encontrada em Sources/VibeDeckApp"; bad=1; }
L=.vibedeck/tests/conceitos-do-produto/9e02c127.sh
for f in $MODEL $SETTINGS; do hasF $L "\"$f\"" "$f lê/grava o limite e precisa estar no LOCAL_OK"; done
finish
