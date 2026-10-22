#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'g.results[index] = Some(run.clone());' "o resultado deve ser gravado na posição de declaração"
hasF $EXEC '.flatten()' "o retorno deve seguir a ordem de declaração"
has $EXEC 'fn results_come_back_in_declaration_order_with_event_pairs' "falta o teste de ordem dos resultados"
hasF $EXEC 'assert_eq!(commands, ["job0", "job1", "job2", "job3", "job4", "job5"]);' "o teste deve comparar a ordem com as primeiras regras mais lentas"
has $RRT 'fn results_keep_declaration_order_under_concurrency' "falta o teste de ordem de run_rule_tests com scripts reais"
finish
