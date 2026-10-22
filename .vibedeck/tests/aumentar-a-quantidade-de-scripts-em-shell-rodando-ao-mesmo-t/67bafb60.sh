#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
f=$(lineof $MODEL 'call\("run_rule_tests"')
w=$(lineof $MODEL 'if withAI \{' "${f:-0}")
c=$(lineof $MODEL 'if execution\.cancelled \{' "${f:-0}")
m=$(lineof $MODEL 'let failed = execution\.steps\.first' "${f:-0}")
for x in "$f" "$w" "$c" "$m"; do [ -n "$x" ] || { echo "$MODEL: estrutura de startRuleExecution mudou"; exit 1; }; done
{ [ "$c" -lt "$w" ] && [ "$m" -lt "$w" ]; } || { echo "$MODEL: cancelamento e falha must devem retornar antes da verificação por IA"; bad=1; }
has $APPT 'func cancelLeavesNoStepRunning' "falta o teste de cancelamento sem passos em andamento"
finish
