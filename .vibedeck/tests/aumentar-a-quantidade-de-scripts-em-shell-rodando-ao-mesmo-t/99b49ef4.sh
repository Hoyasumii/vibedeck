#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
n=$(grep -c 'runner\.run(' Sources/VibeDeckCore/*.swift | awk -F: '{s+=$2} END{print s}')
[ "$n" = 1 ] || { echo "Sources/VibeDeckCore: runner.run deve ser chamado só em runScripts (achei $n chamadas)"; bad=1; }
hasF $PS 'return runScripts(topics.flatMap' "runRuleTests deve chamar runScripts"
hasF $PS 'in runScripts(candidates, files: files, runner: runner)' "submitCheck deve chamar runScripts"
has $CLI 'store\.runRuleTests\(' "o CLI deve usar runRuleTests do Core"
has $CLI 'submitCheck\(' "o CLI deve usar submitCheck do Core"
has $MCP 'store\.submitCheck\(' "o MCP deve usar submitCheck do Core"
none $CLI 'runRuleScripts' "o CLI não deve ter caminho próprio de execução"
none $MCP 'runRuleScripts' "o MCP não deve ter caminho próprio de execução"
finish
