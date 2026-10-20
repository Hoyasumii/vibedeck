#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RT 'let token = cancellation?.onCancel {' "ShellRunner.run deve registrar o cancelamento"
hasF $RT 'terminateTree(process)' "o cancelamento deve terminar o processo"
has $RTT 'func shellRunnerIsCancellable' "falta o teste de cancelamento do ShellRunner"
hasF $RTT 'sleep 30' "o teste deve usar sleep 30"
hasF $RTT 'asyncAfter(deadline: .now() + 0.5)' "o teste deve cancelar após 0,5 s"
hasF $RTT 'Date.now.timeIntervalSince(start) < 5' "o teste deve exigir retorno em menos de 5 s"
finish
