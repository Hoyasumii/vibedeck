#!/usr/bin/env bash
# E6158DCD (D16): sem conexão o app continua mostrando os dados já carregados, em somente leitura; edição recusada até reconectar.
# Análise estática (comportamento só verificável no macOS).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $PM 'static let offlineMessage = "O projeto está offline e somente leitura. Reconecte ao servidor para editar."' "falta a mensagem de somente leitura"
in_body $PM 'private func persist\(' 'if isReadOnly \{' "persist deve recusar edição offline"
in_body $PM 'private func persist\(' 'errorMessage = Self\.offlineMessage' "a recusa da edição offline deve avisar o usuário"
in_body $PM 'private func persist\(' 'restoreLastRead\(\)' "a recusa da edição offline deve voltar à última leitura (sem alteração otimista)"
in_body $PM 'func refresh\(' 'if isReadOnly \{ return \}' "offline não se relê (os dados em tela continuam os da última leitura)"
in_body $PM 'private func persistFailed\(' 'link\?\.noteFailure\(error\)' "uma gravação que falha por perda de conexão deve colocar o link offline"
need Sources/VibeDeckApp/V2/V2ContentColumn.swift '\.disabled\(model\.isReadOnly\)' "as ações de edição da lista devem ficar desabilitadas offline"
need Sources/VibeDeckApp/DocView.swift '\.disabled\(model\.isReadOnly\)' "a edição do doc deve ficar desabilitada offline"
need Sources/VibeDeckApp/V2/V2ProjectWindow.swift 'model\.isReadOnly' "a janela deve reagir ao modo somente leitura"
finish
