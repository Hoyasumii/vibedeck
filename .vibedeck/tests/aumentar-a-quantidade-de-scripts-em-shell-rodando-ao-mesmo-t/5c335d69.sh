#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $TASKS 'let runs = run_scripts(' "submit_check não chama run_scripts"
hasF $TASKS 'submit_check_with(store, params, runner, &RunOptions::default(), &|_| {})' "submit_check deve usar as opções padrão"
none $TASKS 'stop_on_must_failure' "submit_check não pode parar na falha must"
none $RCLI 'stop_on_must_failure' "o CLI não pode pedir parada na falha must"
none $RMCP 'stop_on_must_failure' "o MCP não pode pedir parada na falha must"
hasF $TASKS '// Todo script roda, mesmo depois de um `must` reprovado: o check responde a todas as regras.' "falta o comentário/invariante de submit_check"
finish
