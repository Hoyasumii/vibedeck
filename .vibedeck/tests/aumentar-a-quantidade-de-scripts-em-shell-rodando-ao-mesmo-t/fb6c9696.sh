#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $MODEL 'func begin\(_ ids' "RuleExecutionModel.begin ausente"
hasF $MODEL 'steps[index].started = now' "begin deve marcar só o passo iniciado"
hasF $VIEW 'return step.started == nil ? "Aguardando" : "Executando"' "a view deve mostrar Executando para todo passo iniciado e sem fim"
hasF $APPT 'parallel steps show as running' "falta o teste com 2+ passos em andamento"
none $MODEL 'first\(where: \{ \$0\.started != nil && \$0\.ended == nil' "o modelo não pode destacar um único passo em andamento"
finish
