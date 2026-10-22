#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# Cancelar ou interromper nunca grava check: submit_rule_check tem um único ponto de chamada, depois do retorno por cancelamento.
f=$(lineof $MODEL 'call\("run_rule_tests"')
c=$(lineof $MODEL 'if execution\.cancelled \{' "${f:-0}")
s=$(lineof $MODEL 'call\("submit_rule_check"' "${f:-0}")
{ [ -n "$c" ] && [ -n "$s" ] && [ "$c" -lt "$s" ]; } || { echo "$MODEL: submit_rule_check deve vir só depois do retorno por cancelamento"; bad=1; }
[ "$(grep -c '"submit_rule_check"' $MODEL)" = 1 ] || { echo "$MODEL: submit_rule_check deve ter um único ponto de chamada"; bad=1; }
hasF $APPT '#expect(execution.saved == false)' "o teste deve exigir que cancelar não marque a execução como salva"
finish
