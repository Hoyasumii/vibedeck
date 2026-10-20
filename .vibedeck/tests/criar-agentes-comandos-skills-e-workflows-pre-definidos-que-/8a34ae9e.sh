#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$PMODEL" 'func addKitItems\(_ refs: \[String\], undo: UndoManager\?\)' "ProjectModel.addKitItems com undo ausente"
n=$(awk '/func addKitItems\(_ refs/{f=1} f&&/registerUndo\(/{c++} f&&/^    private struct KitFileState/{exit} END{print c+0}' "$PMODEL")
[ "$n" -eq 1 ] || { echo "$PMODEL: addKitItems deve registrar exatamente 1 passo de undo (achei $n)"; fail=1; }
need "$PMODEL" 'reloadKitItems\(\)' "lista deve recarregar ao vivo"
need "$VIEW" 'model\.addKitItems\(\$0, undo: undo\)' "UI deve passar o UndoManager"
need "$APPT" 'undo\.undo\(\)' "teste de undo ausente"
need "$APPT" 'entireSelectionIsLiveAndHasOneUndoWithRedo' "teste do undo único ausente"
finish
