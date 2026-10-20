#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$INST" 'createAgent' "usa createAgent"
forbid "$INST" 'JSONEncoder|VDJSON\.encode' "instalação não deve ter formato próprio de arquivo"
need "$CORET" 'SchemaURL\.workflow' "teste de schema do workflow ausente"
for s in agent command skill; do need "$CORET" "SchemaURL\.$s" "teste de schema $s ausente"; done
need "$CORET" 'loadWorkflow' "teste de leitura via ProjectStore ausente"
finish
