#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# A1A13E0F: criação, alteração e exclusão nos dados do projeto SSH chegam à pasta remota (o Core roda lá, via MCP por SSH).
needF $STATUS 'struct V2RemoteEnvironmentSegment: View' "o projeto SSH deve exibir o estado da conexão"
needF $STATUSBAR 'V2RemoteEnvironmentSegment(link: link)' "a barra de status do projeto SSH deve mostrar a conexão"
# Edição só com conexão: offline o app recusa gravar (nada é gravado fora do servidor).
in_body $PM 'private func persist\(' 'if isReadOnly \{' "sem conexão a gravação deve ser recusada (somente leitura)"
in_body $CSTORE 'static func sshLocation' 'RemoteExecution\.launcher\("vibedeck"' "o Core do projeto SSH deve rodar no servidor (ssh host vibedeck mcp)"
in_body $CSTORE 'static func sshLocation' 'connection\.commandArguments\(login\)' "o Core remoto deve ser lançado pelo ssh do destino"
needF $CSTORE 'self.location = try CoreStore.sshLocation(for: workspace)' "abrir uma raiz ssh:// deve usar a localização SSH"
# Sem espelho local: nada de cache/sincronização no app.
forbid $WS 'synchronize|pendingCount|conflictFiles' "o projeto SSH não deve manter espelho local nem sincronização"
# O Core grava de forma atômica na pasta do servidor.
need crates/vibedeck-core/src/store.rs 'pub fn write_atomic' "o Core Rust deve gravar de forma atômica"
finish
