#!/usr/bin/env bash
# Abrir/fechar o visualizador não chama model.mutateProject nem registra undo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

open=$(block 'private func open[(]_ link: ProjectLink[)]')
[ -n "$open" ] || bad "$F: open(_:) não encontrado"
deny "$open" 'mutateProject|undo|registerUndo|save' "open(_:) não pode alterar o projeto nem o undo"
deny "$(grep -n 'viewing' "$F")" 'mutateProject|undo|registerUndo' "uso de viewing não pode alterar o projeto"
need "$(block '^struct LinksView: View')" 'LinkViewerPanel\(link: viewing\) \{ self\.viewing = nil \}' "fechar deve só zerar viewing"
viewer="$(block '^private struct LinkViewerPanel')"$'\n'"$(block 'struct LinkWebView: NSViewRepresentable')"
deny "$viewer" 'mutateProject|undoManager|registerUndo|ProjectModel|FileManager|\.write\(to|createFile' "visualizador não pode alterar arquivos do projeto nem undo"
exit $fail
