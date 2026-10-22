#!/usr/bin/env bash
# A6181C00: antes de enviar, compara o arquivo remoto com a base da edição; se mudou, bloqueia (conflito).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $WS 'public func synchronize\(using')
grep -qF 'conflictFiles[path] = Conflict(path: path, local: local, remote: server)' <<<"$B" || { echo "$WS: mudança remota em arquivo editado deve virar conflito"; fail=1; }
in_body $WS 'public func replace\(' 'cmp -s " \+ quoted \+ " " \+ baseQuote' "o servidor deve conferir a versão base antes de sobrescrever"
in_body $WS 'public func replace\(' 'test ! -e " \+ quoted' "criação deve falhar se o arquivo apareceu no servidor"
run_tests conflictPreservesBothAcrossRestartUntilChoice workflowStateSynchronizesBeforeProviderAndStillBlocksConflicts
finish
