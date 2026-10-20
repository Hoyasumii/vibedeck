#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RT 'cancellation: ShellCancellation? = nil' "ShellRunner.run deve aceitar cancelamento"
hasF $RT 'terminateTree(process)' "o cancelamento deve terminar o processo"
hasF $PS 'cancellation?.isCancelled != true' "a fila não deve iniciar novos scripts depois do cancelamento"
has $RE 'func cancellationStopsQueueAndRunningScripts' "falta o teste de cancelamento no Core"
hasF $RE 'terminated.values == ["one"]' "o teste deve exigir terminate no script ativo"
hasF $RE 'events.values == ["one"]' "o teste deve exigir que nenhum .started novo seja emitido"
has $APPT 'func cancelTerminatesScriptsAndSkipsAIAndSaving' "falta o teste de cancelamento no app"
finish
