#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 384B5C03: itens do catálogo ficam em arquivos do repo, no mesmo formato dos criados à mão (mesmo caminho de gravação).
need "$KITS" 'persona::create::<Agent>' "agente deve ser criado por persona::create"
need "$KITS" 'persona::create::<Command>' "comando deve ser criado por persona::create"
need "$KITS" 'persona::create::<Skill>' "skill deve ser criada por persona::create"
need "$KITS" 'store\.save::<Workflow>' "workflow deve ser gravado por Store::save"
forbid "$KITS" 'serde_json::to_|to_string_pretty|std::fs::write|File::create' "instalação não deve ter formato próprio de arquivo"
need "$PERSONA" 'save\(store, &slug, &value\)' "persona::create deve gravar pelo Store"
finish
