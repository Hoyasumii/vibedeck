#!/usr/bin/env bash
# Seletor de workflow da implementação oferece o catálogo
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
cw=$(block "$SHEET" '} else if choosingWorkflow {')
grep -q 'KitCatalogButton()' <<<"$cw" || { echo "$WFV: seletor de workflow sem acesso ao catálogo (KitCatalogButton)"; bad=1; }
has Sources/VibeDeckApp/KitCatalogView.swift 'KitCatalogSheet \{ model.addKitItems\(\$0, undo: undo\) \}' "KitCatalogButton não adiciona itens do catálogo"
# Workflow adicionado aparece na lista (model.workflows é recarregado)
inblock "$MODEL" 'func addKitItems' 'reloadKitItems\(\)|reloadWorkflows\(\)' "addKitItems não recarrega a lista de workflows"
finish
