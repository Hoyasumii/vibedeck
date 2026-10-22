#!/usr/bin/env bash
# F6C6F8A2: arquivo editado offline e apagado no servidor é recriado no caminho original.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $WS '(server == nil && local != nil)' "apagado no servidor + editado localmente deve ser recriado"
in_body $WS 'public func replace\(' 'mkdir -p " \+ SSHConnection\.quote\(parent' "a recriação deve restaurar as pastas do caminho original"
run_tests recreateFileDeletedOnServer
finish
