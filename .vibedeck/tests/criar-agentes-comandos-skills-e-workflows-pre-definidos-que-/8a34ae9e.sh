#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 8A34AE9E (should): adicionar item do catálogo aceita um único passo de undo no app e aparece ao vivo na lista, sem recarregar.
need "$PMODEL" 'func addKitItems\(_ refs: \[String\], undo: UndoManager\?\)' "ProjectModel.addKitItems com undo ausente"
b=$(awk '/func addKitItems\(_ refs/{f=1} f{print} f&&/^    }$/{exit}' "$PMODEL")
n=$(grep -c 'registerUndo(' <<<"$b" || true)
[ "$n" -eq 1 ] || { echo "$PMODEL: addKitItems deve registrar exatamente 1 passo de undo (achei $n)"; fail=1; }
grep -q 'reloadKitItems()' <<<"$b" || { echo "$PMODEL: a lista deve recarregar ao vivo após adicionar"; fail=1; }
need "$VIEW" 'model\.addKitItems\(\$0, undo: undo\)' "UI deve passar o UndoManager"
finish
