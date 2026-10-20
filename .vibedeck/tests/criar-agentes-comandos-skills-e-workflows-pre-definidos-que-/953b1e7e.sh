#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
forbid "$CAT" 'readOnly|locked|immutable|isLocked' "itens do catálogo não podem ser bloqueados"
need "$INST" 'tags: \["kit"\]' "instalação deve marcar apenas com tag ordinária"
forbid "$PMODEL" 'catalog.*(revert|restore|reset)|(revert|reset).*[Kk]it' "catálogo não deve reverter edições"
need "$CORET" 'updateAgent\(agent\.slug\)' "teste de edição após instalação ausente"
need "$CORET" 'updateWorkflow\(workflow\.slug\)' "teste de edição de workflow ausente"
need "$CORET" 'first\.map \{ try Data\(contentsOf: url' "teste de que a edição persiste ao readicionar ausente"
finish
