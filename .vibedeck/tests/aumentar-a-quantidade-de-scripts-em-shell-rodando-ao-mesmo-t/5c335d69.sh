#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $TASKS 'for run in run_scripts(' "submit_check não chama run_scripts"
hasF $TASKS '&RunOptions::default(),' "submit_check deve usar as opções padrão"
none $TASKS 'stop_on_must_failure|cancellation:' "submit_check não pode parar na falha must nem ser cancelado"
hasF $TASKS '// Todo script roda, mesmo depois de um `must` reprovado: o check responde a todas as regras.' "falta o comentário/invariante de submit_check"
finish
