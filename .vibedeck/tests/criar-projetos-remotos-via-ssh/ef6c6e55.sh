#!/usr/bin/env bash
# EF6C6E55: um caminho remoto digitado é navegado/selecionado (Return, Ir ou Abrir).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $SHEET 'LoggedTextField("Diretório remoto", text: $path)' "falta o campo de caminho remoto"
needF $SHEET '.onSubmit { navigate(path) }' "Return no caminho deve navegar até ele"
needF $SHEET 'LoggedButton("Ir") { navigate(path) }' "falta o botão Ir"
in_body $SHEET 'private func openSelected' 'let requestedPath = path' "Abrir deve usar o caminho digitado"
in_body $SHEET 'private func openSelected' 'resolved\(directory: requestedPath\)' "o caminho digitado deve ser resolvido no servidor antes de abrir"
finish
