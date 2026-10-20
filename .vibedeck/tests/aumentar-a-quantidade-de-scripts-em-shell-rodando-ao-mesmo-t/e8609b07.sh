#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'if stopOnMustFailure, job.rule.severity == .must, outcome.verdict == .fail { state.stopped = true }' "falha must deve parar a fila"
hasF $PS 'while !state.pending.isEmpty, !state.stopped' "o laço deve parar quando a fila é interrompida"
has $RE 'func mustFailureStopsQueueOnlyWhenAsked' "falta o teste de falha must"
hasF $RE 'started.values == ["fail"]' "o teste deve exigir que nenhuma regra seguinte inicie"
hasF $MODEL 'stopOnMustFailure: true' "o app deve pedir a parada em falha must"
finish
