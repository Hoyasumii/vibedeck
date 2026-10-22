# Helpers do tópico exibir-o-grafo-de-graphify-em-algum-lugar-do-app (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
G=Sources/VibeDeckApp/GraphView.swift
PG=crates/vibedeck-core/src/project/graph.rs
GJS=Sources/VibeDeckApp/GraphResources/graph.js
RGJS=crates/vibedeck-core/assets/graph/graph.js
PW=Sources/VibeDeckApp/V2/V2ProjectWindow.swift
NAV=Sources/VibeDeckApp/V2/V2Navigation.swift
COL=Sources/VibeDeckApp/V2/V2ContentColumn.swift
TB=Sources/VibeDeckApp/TabBar.swift
PM=Sources/VibeDeckApp/ProjectModel.swift
fail=0
# applies: 77 se a tarefa não tocou nos arquivos do tópico.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -E '^Sources/VibeDeckApp/(GraphView|TabBar|ProjectModel)\.swift$|^Sources/VibeDeckApp/V2/|^Sources/VibeDeckApp/GraphResources/graph\.js$|^crates/vibedeck-core/src/project/graph\.rs$|^crates/vibedeck-core/assets/graph/' >/dev/null; then exit 77; fi
bad() { echo "$1: $2"; fail=1; }
# need <arquivo> <regex> <motivo>: exige que o regex (ERE) apareça no arquivo.
need() { grep -qE "$2" "$1" || bad "$1:1" "$3"; }
# forbid <arquivo> <regex> <motivo>: proíbe o regex, apontando a linha.
forbid() { local l; l=$(grep -nE "$2" "$1" | head -1 || true); [ -z "$l" ] || bad "$1:${l%%:*}" "$3"; }
