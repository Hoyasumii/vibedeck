#!/usr/bin/env bash
# AF0519D5 (D16): projeto SSH já lido reabre offline, somente leitura, com a última leitura em cache e estado desconectado indicado.
# Análise estática; o round-trip do cache é coberto por CoreModelsTests.remoteCacheRoundTrips (swift test, só no macOS).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $LINK 'struct RemoteCache: Codable' "falta RemoteCache (última leitura em disco)"
need $LINK 'appending\(path: "RemoteCache"' "o cache deve ficar em Application Support/VibeDeck/RemoteCache"
in_body $LINK 'static func url\(for workspace' 'workspace\.destination\.id' "o cache deve ser por destino"
in_body $PM 'static func open\(root' 'RemoteCache\.load\(for: workspace\)' "abrir um projeto SSH inalcançável deve usar o cache"
in_body $PM 'static func open\(root' 'connected: false' "o projeto aberto do cache deve nascer desconectado"
in_body $PM 'static func open\(root' 'apply\(runs: cache\.runs' "o cache deve restaurar também execuções, checks e textos de docs"
need $PM 'var isReadOnly: Bool \{' "falta isReadOnly (somente leitura sem conexão)"
in_body $PM 'var isReadOnly' 'return !link\.isConnected' "somente leitura = projeto SSH sem conexão"
in_body $PM 'func scheduleCacheCapture\(' 'RemoteCache\.save\(' "a última leitura deve ser gravada no cache"
needF $PM 'if let workspace = RemoteWorkspace.existing(at: store.root) {' "o modelo deve criar o RemoteLink do projeto SSH"
needF Sources/VibeDeckApp/V2/V2ProjectWindow.swift 'V2OfflineBanner(link: link)' "a janela deve indicar claramente o estado desconectado"
needF $STATUS 'case .offline: return "offline (somente leitura)"' "a barra de status deve indicar offline somente leitura"
needF $CTESTS 'func remoteCacheRoundTrips' "falta o teste do cache"
finish
