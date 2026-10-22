#!/usr/bin/env bash
# Sem workflows: só Execução padrão e Cancelar
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
d=$(segment "$SHEET" 'Text("Como deseja implementar esta ideia?")' 'HStack {')
[ -n "$d" ] || { echo "$WFV: diálogo de modo não encontrado"; bad=1; }
python3 -I - "$d" <<'PY' || bad=1
import re,sys
d=sys.argv[1]
i=d.find('if !model.workflows.isEmpty {'); w=d.find('LoggedButton("Workflow")')
if i<0 or w<0 or w<i or d.find('}',i)<w: print("WorkflowView.swift: botão Workflow deve ficar dentro de 'if !model.workflows.isEmpty'"); sys.exit(1)
if 'KitCatalogButton' in d: print("WorkflowView.swift: diálogo de modo não deve oferecer catálogo"); sys.exit(1)
if 'ForEach' in d: print("WorkflowView.swift: diálogo de modo não deve listar workflows"); sys.exit(1)
PY
grep -q 'LoggedButton("Execução padrão")' <<<"$d" || { echo "$WFV: Execução padrão ausente"; bad=1; }
hasF "$SHEET" 'LoggedButton("Cancelar", role: .cancel)' "Cancelar ausente"
t=$(block "$SHEET" '.task {')
grep -q 'else if !model.workflows.isEmpty { choosingWorkflow = true }' <<<"$t" || { echo "$WFV: modo workflow sem nome deve abrir seletor só quando há workflows"; bad=1; }
finish
