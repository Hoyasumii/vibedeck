#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# A1A13E0F: criação, alteração e exclusão nos dados do projeto SSH chegam à pasta remota (o Core roda lá, via MCP por SSH).
need $STATUS 'RemoteProjectStatus\(workspace\)' "o projeto SSH deve exibir o estado da conexão"
need Sources/VibeDeckApp/V2/V2StatusBar.swift 'V2RemoteEnvironmentSegment\(workspace: workspace\)' "a barra de status do projeto SSH deve mostrar a conexão"
in_body $CSTORE 'static func sshLocation' 'RemoteExecution\.launcher\("vibedeck"' "o Core do projeto SSH deve rodar no servidor (ssh host vibedeck mcp)"
in_body $CSTORE 'static func sshLocation' 'connection\.commandArguments\(login\)' "o Core remoto deve ser lançado pelo ssh do destino"
needF $CSTORE 'self.location = try CoreStore.sshLocation(for: workspace)' "abrir uma raiz ssh:// deve usar a localização SSH"
# Sem espelho local: nada de cache/sincronização no app.
forbid $WS 'synchronize|pendingCount|conflictFiles' "o projeto SSH não deve manter espelho local nem sincronização"
# O Core grava de forma atômica na pasta do servidor.
need crates/vibedeck-core/src/store.rs 'pub fn write_atomic' "o Core Rust deve gravar de forma atômica"
finish
