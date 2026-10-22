#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
n=$(grep -rn 'runner\.run(' crates/vibedeck-core/src crates/vibedeck/src | grep -v '^[^:]*tests' | wc -l | tr -d ' ')
[ "$n" = 1 ] || { echo "crates: runner.run deve ser chamado só em run_scripts (achei $n chamadas)"; bad=1; }
hasF $TASKS 'Ok(run_scripts(' "run_rule_tests deve chamar run_scripts"
hasF $TASKS 'for run in run_scripts(' "submit_check deve chamar run_scripts"
has $RCLI 'rules::run_rule_tests\(' "o CLI deve usar run_rule_tests do Core"
has $RCLI 'rules::submit_check\(' "o CLI deve usar submit_check do Core"
has $RMCP 'rules::submit_check\(' "o MCP deve usar submit_check do Core"
has $RMCP 'rules::run_rule_tests\(' "o MCP deve usar run_rule_tests do Core"
none $RCLI 'run_scripts|run_rule_scripts' "o CLI não deve ter caminho próprio de execução"
none $RMCP 'run_scripts|run_rule_scripts' "o MCP não deve ter caminho próprio de execução"
finish
