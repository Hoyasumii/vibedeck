#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RUN 'c.on_cancel(move || flag.store(true, Ordering::SeqCst))' "run_shell deve registrar o cancelamento"
hasF $RUN 'terminate_tree(pid);' "o cancelamento deve terminar o processo"
has $RUN 'fn cancellation_before_and_during' "falta o teste de cancelamento do run_shell"
hasF $RUN 'run_shell("echo rodando; sleep 30"' "o teste deve usar sleep 30"
hasF $RUN 'assert_eq!(r.status, 130);' "o teste deve exigir status 130"
hasF $RRT 'assert!(started.elapsed() < Duration::from_secs(10));' "o teste de integração deve exigir retorno rápido"
finish
