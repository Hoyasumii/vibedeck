#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
f=$(lineof $MODEL 'for await event in events')
w=$(lineof $MODEL 'if withAI \{' "${f:-0}")
c=$(lineof $MODEL 'if execution\.cancelled \{' "${f:-0}")
m=$(lineof $MODEL 'let failed = execution\.steps\.first' "${f:-0}")
for x in "$f" "$w" "$c" "$m"; do [ -n "$x" ] || { echo "$MODEL: estrutura de startRuleExecution mudou"; exit 1; }; done
{ [ "$c" -lt "$w" ] && [ "$m" -lt "$w" ]; } || { echo "$MODEL: cancelamento e falha must devem retornar antes da verificação por IA"; bad=1; }
has $APPT 'func mustFailureInterruptsWithoutAI' "falta o teste de falha must sem IA"
hasF $APPT '#expect(aiCalls == 0)' "o teste deve exigir que verify não seja chamado"
finish
