#!/usr/bin/env bash
# 131C047E: pasta remota com vibedeck.json abre seu próprio projeto; pastas distintas têm caches distintos.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN 'public var id: String { Self.digest("\(connectionID)\u{0}\(directory)") }' "a identidade do projeto deve incluir o diretório remoto"
in_body $WS 'public static func open\(' 'cache\.appending\(path: destination\.id\)' "cada destino/diretório deve ter seu cache"
B=$(body $SHEET 'private func openSelected')
grep -qF 'if snapshot["vibedeck.json"] == nil && !create' <<<"$B" || { echo "$SHEET: abrir deve verificar vibedeck.json na pasta remota"; fail=1; }
grep -qF 'workspace.synchronize(using: transport)' <<<"$B" || { echo "$SHEET: abrir deve carregar os dados da pasta remota"; fail=1; }
grep -qF 'onOpen(workspace.root)' <<<"$B" || { echo "$SHEET: abrir deve exibir o projeto da pasta"; fail=1; }
need $APPF 'ProjectWindow\(root: root\)' "o projeto aberto deve ser exibido"
needF $APPF '.id(root)' "cada pasta deve ter sua própria janela de projeto"
run_tests destinationValidationAndIsolation pendingEditsAreIsolatedPerDestination
finish
