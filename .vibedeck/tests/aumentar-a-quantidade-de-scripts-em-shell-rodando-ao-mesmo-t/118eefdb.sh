#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# O Core Rust não lê preferências do app: só os dois arquivos do app tocam a chave do limite.
L=.vibedeck/tests/conceitos-do-produto/9e02c127.sh
hasF $MODEL "ruleScriptConcurrency" "$MODEL deveria definir a chave do limite"
hasF $SETTINGS "RuleExecutionModel.concurrencyKey" "$SETTINGS deveria usar a chave do limite"
others=$(grep -rl 'ruleScriptConcurrency\|concurrencyKey' Sources/VibeDeckApp --include='*.swift' | grep -v -e "^$MODEL\$" -e "^$SETTINGS\$" || true)
[ -z "$others" ] || { echo "só $MODEL e $SETTINGS podem usar a chave do limite; achei em: $others"; bad=1; }
none_in_core=$(grep -rl 'ruleScriptConcurrency\|UserDefaults' crates schema --include='*.rs' --include='*.json' 2>/dev/null || true)
[ -z "$none_in_core" ] || { echo "Core/CLI/MCP não podem usar UserDefaults nem a chave do limite: $none_in_core"; bad=1; }
out=$(VIBEDECK_FILES= bash $L 2>&1) || { echo "$L falhou:"; echo "$out"; bad=1; }
finish
