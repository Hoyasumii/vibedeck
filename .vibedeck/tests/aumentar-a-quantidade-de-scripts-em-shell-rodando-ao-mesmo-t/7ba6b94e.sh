#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RUN 'terminate_tree(pid);' "o cancelamento deve terminar o processo"
hasF $RUN 'if cancel_flag.load(Ordering::SeqCst) {' "run_shell deve observar o cancelamento"
hasF $EXEC 'while !guard.pending.is_empty() && !guard.stopped && !cancelled() {' "a fila não deve iniciar novos scripts depois do cancelamento"
has $EXEC 'fn cancellation_stops_the_queue_and_running_scripts' "falta o teste de cancelamento no Core"
hasF $EXEC 'assert_eq!(started.load(Ordering::SeqCst), 1);' "o teste deve exigir que nenhum script novo inicie"
hasF $EXEC 'assert_eq!(runs[0].outcome.exit_code, 130);' "o teste deve exigir que o script ativo seja cancelado"
finish
