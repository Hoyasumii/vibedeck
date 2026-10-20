#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $APPT '#expect(((try? FileManager.default.contentsOfDirectory(atPath: checks.path)) ?? []) == before)' "o teste deve exigir que cancelar não crie check"
f=$(lineof $MODEL 'for await event in events')
c=$(lineof $MODEL 'if execution\.cancelled \{' "${f:-0}")
s=$(lineof $MODEL 'completeRuleExecution' "${f:-0}")
{ [ -n "$c" ] && [ -n "$s" ] && [ "$c" -lt "$s" ]; } || { echo "$MODEL: completeRuleExecution deve vir só depois do retorno por cancelamento"; bad=1; }
[ "$(grep -c 'completeRuleExecution' $MODEL)" = 1 ] || { echo "$MODEL: completeRuleExecution deve ter um único ponto de chamada"; bad=1; }
finish
