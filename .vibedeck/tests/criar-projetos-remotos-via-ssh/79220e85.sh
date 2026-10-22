#!/usr/bin/env bash
# 79220E85: ao reconectar, pendências sem conflito são enviadas.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $WS '} else if server == ancestor || (server == nil && local != nil) {' "pendências sem conflito devem ser enviadas"
needF $WS 'try transport.replace(path, expected: server, with: local)' "o envio deve usar a versão local"
in_body $SHEET 'func synchronize\(force' 'connect\(password: secret\)' "a reconexão deve preceder o envio"
run_tests durableEditsDeletionAndRestart workflowStateSynchronizesBeforeProviderAndStillBlocksConflicts
finish
