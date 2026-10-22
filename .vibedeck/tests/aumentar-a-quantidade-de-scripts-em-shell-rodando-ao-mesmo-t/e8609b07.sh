#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'g.stopped = true;' "falha must deve parar a fila"
hasF $EXEC '&& job.rule.severity == crate::model::RuleSeverity::Must' "só a falha de regra must deve parar a fila"
hasF $EXEC 'while !guard.pending.is_empty() && !guard.stopped && !cancelled() {' "o laço deve parar quando a fila é interrompida"
has $EXEC 'fn must_failure_stops_the_queue_only_when_asked' "falta o teste de falha must"
hasF $EXEC 'assert_eq!(stopped.len(), 1);' "o teste deve exigir que nenhuma regra seguinte inicie"
none $RCLI 'stop_on_must_failure' "o CLI não deve parar a fila em falha must"
none $RMCP 'stop_on_must_failure' "o MCP não deve parar a fila em falha must"
finish
