#!/usr/bin/env bash
# C9A681C0: pendências pertencem a servidor+porta+usuário+diretório; nunca vão para outro destino.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN 'public var connectionID: String { Self.digest("\(host)\u{0}\(port)\u{0}\(user)") }' "a conexão deve ser identificada por servidor, porta e usuário"
needF $CONN 'public var id: String { Self.digest("\(connectionID)\u{0}\(directory)") }' "o projeto deve ser identificado também pelo diretório"
needF $WS 'guard state.destination == destination else' "o cache deve recusar outro destino"
in_body $SHEET 'func synchronize\(force' 'SSHFileTransport\(workspace\.destination\)' "a sincronização deve usar o destino de origem das pendências"
run_tests destinationValidationAndIsolation pendingEditsAreIsolatedPerDestination
finish
