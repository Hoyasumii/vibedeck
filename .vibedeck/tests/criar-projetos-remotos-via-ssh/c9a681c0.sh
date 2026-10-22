#!/usr/bin/env bash
# C9A681C0 (D16): o cache da última leitura é associado ao servidor, porta, usuário e diretório remoto de origem.
# Análise estática (destinos com o mesmo caminho em servidores distintos não compartilham cache).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN 'var connectionID: String { Self.digest("\(host)\u{0}\(port)\u{0}\(user)") }' "connectionID deve cobrir servidor, porta e usuário"
needF $CONN 'var id: String { Self.digest("\(connectionID)\u{0}\(directory)") }' "o id do destino deve incluir também o diretório remoto"
in_body $LINK 'static func url\(for workspace' 'workspace\.destination\.id \+ "\.json"' "o arquivo de cache deve ser nomeado pelo id do destino"
finish
