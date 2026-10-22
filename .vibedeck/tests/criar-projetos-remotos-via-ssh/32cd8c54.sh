#!/usr/bin/env bash
# 32CD8C54 (D16): a interface distingue projeto SSH conectado, reconectando (próxima tentativa em Ns) e offline somente leitura.
# Análise estática (comportamento só verificável no macOS).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
for s in connected connecting 'waiting\(until: Date\)' offline; do
  need $LINK "case $s" "RemoteLink.State sem o estado $s"
done
in_body $STATUS 'private func detail\(now' 'case \.connected: return "conectado"' "o segmento deve mostrar conectado"
in_body $STATUS 'private func detail\(now' 'case \.connecting: return "reconectando…"' "o segmento deve mostrar reconectando"
in_body $STATUS 'private func detail\(now' 'próxima tentativa em' "o segmento deve mostrar a contagem da próxima tentativa"
in_body $STATUS 'private func detail\(now' 'offline \(somente leitura\)' "o segmento deve mostrar offline somente leitura"
needF $STATUSBAR 'V2RemoteEnvironmentSegment(link: link)' "a barra de status deve mostrar o estado da conexão SSH"
needF Sources/VibeDeckApp/V2/V2ProjectWindow.swift 'V2OfflineBanner(link: link)' "o aviso de offline deve aparecer na janela"
finish
