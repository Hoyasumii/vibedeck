#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $MODEL 'func interrupt(' "falta RuleExecutionModel.interrupt"
hasF $MODEL 'steps[index].skipped = true' "passos que não iniciaram devem ficar marcados como não executados"
hasF $MODEL 'steps[index].ended = now; steps[index].error' "passos em andamento devem ser encerrados"
hasF $VIEW 'return "Não executado"' "a view deve mostrar Não executado"
hasF $APPT 'execution.steps.allSatisfy { !($0.started != nil && $0.ended == nil) }' "o teste deve exigir nenhum passo em andamento após cancelar"
finish
