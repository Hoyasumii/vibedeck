#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 131C047E: pasta remota com vibedeck.json abre seu próprio projeto; pastas distintas têm identidades e janelas distintas.
needF $CONN 'var id: String { Self.digest("\(connectionID)\u{0}\(directory)") }' "a identidade do projeto deve incluir o diretório remoto"
in_body $WS 'static func rootURL' 'components\.path = destination\.directory' "a raiz da janela (ssh://…) deve incluir o diretório remoto"
B=$(body $SHEET 'private func openSelected')
grep -qF 'test -f vibedeck.json && printf yes || printf no' <<<"$B" || { echo "$SHEET: abrir deve verificar vibedeck.json na pasta remota"; fail=1; }
grep -qF 'onOpen(RemoteWorkspace.rootURL(for: destination))' <<<"$B" || { echo "$SHEET: abrir deve exibir o projeto da pasta"; fail=1; }
need $APPF 'ProjectWindowV2\(root: root\)' "o projeto aberto deve ser exibido"
needF $APPF '.id(root)' "cada pasta deve ter sua própria janela de projeto"
# O Core do projeto roda no diretório remoto escolhido (`vibedeck mcp -C <dir>`), então cada pasta mostra seus próprios dados.
in_body $CSTORE 'static func sshLocation' 'arguments: \["mcp",[^]]*"-C", workspace\.destination\.directory\]' "o Core remoto deve abrir exatamente a pasta selecionada"
finish
