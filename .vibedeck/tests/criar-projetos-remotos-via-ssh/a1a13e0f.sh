#!/usr/bin/env bash
# A1A13E0F: criação, alteração e exclusão nos dados do projeto SSH são sincronizadas com a pasta remota.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckCore/ProjectStore\.swift$'
need $WINDOW 'RemoteWorkspace\.existing\(at: model\.store\.root\).*RemoteProjectBar\(workspace: workspace\)' "o projeto SSH deve exibir a barra de sincronização"
in_body $SHEET '^struct RemoteProjectBar' 'await status\.synchronize\(\)' "a barra deve sincronizar continuamente"
in_body $SHEET 'func synchronize\(force' 'workspace\.synchronize\(using: SSHFileTransport\(workspace\.destination\)\)' "a sincronização deve enviar para o destino SSH do projeto"
in_body $WS 'public func replace\(' 'rm -f " \+ quoted' "exclusões devem ser aplicadas no servidor"
in_body $WS 'public func replace\(' 'mv -f " \+ tempQuote \+ " " \+ quoted' "criações/alterações devem ser gravadas no servidor"
run_tests projectEditsSynchronizeAndContinueOffline durableEditsDeletionAndRestart remoteChangesRefreshCacheAndLocalFilesStayLocal
finish
