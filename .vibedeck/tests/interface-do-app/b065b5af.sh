#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Um UndoManager por doc/ideia, vindo de model.undoManager(forDoc:), e o NSTextView usa o do editor.
pm=Sources/VibeDeckApp/ProjectModel.swift
grep -q 'func undoManager(forDoc' "$pm" || bad "$pm" "undoManager(forDoc:) ausente"
grep -q 'docUndoManagers\[slug\]' "$pm" || bad "$pm" "histórico por slug (docUndoManagers) ausente"
grep -q 'model.undoManager(forDoc: slug)' Sources/VibeDeckApp/DocView.swift || bad Sources/VibeDeckApp/DocView.swift "DocView não usa model.undoManager(forDoc: slug)"
grep -q 'model.undoManager(forDoc: "idea:\\(slug)")' Sources/VibeDeckApp/IdeaView.swift || bad Sources/VibeDeckApp/IdeaView.swift "IdeaView não usa a chave idea:<slug>"
me=Sources/VibeDeckApp/MarkdownEditor.swift
grep -q 'func undoManager(for view: NSTextView) -> UndoManager? { parent.undoManager }' "$me" || bad "$me" "NSTextView não devolve o UndoManager do doc"
# Nenhum MarkdownEditor criado com um UndoManager() avulso.
while IFS=: read -r f n line; do bad "$f:$n" "UndoManager() avulso (use model.undoManager(forDoc:))"; done < <(grep -nE 'UndoManager\(\)' Sources/VibeDeckApp/*.swift | grep -v 'ProjectModel.swift' | sed 's/:/:/' | awk -F: '{print $1":"$2":"$3}' || true)
exit $fail
