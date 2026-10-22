#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# A21B5419: adicionar do catálogo passa pelas operações de criação do Core (persona::create / Store::save) e grava via escrita atômica.
for fn in 'persona::create::<Agent>' 'persona::create::<Command>' 'persona::create::<Skill>' 'create_workflow\(store'; do
  need "$KITS" "$fn" "add_kit_items deve usar $fn"
done
forbid "$KITS" 'std::fs::|File::create|OpenOptions' "instalação não deve escrever arquivos diretamente"
# Store::save (usado por persona::save) grava com write_atomic.
b=$(awk '/pub fn save<T: Stored>/{f=1} f{print} f&&/^    }$/{exit}' crates/vibedeck-core/src/store.rs)
grep -q 'write_atomic\|write_if_changed' <<<"$b" || { echo "crates/vibedeck-core/src/store.rs: Store::save não grava de forma atômica"; fail=1; }
grep -q 'write_if_changed\|fn write_atomic' crates/vibedeck-core/src/store.rs || { echo "store.rs: falta escrita atômica"; fail=1; }
need "$PMODEL" 'store\.call\("add_kit"' "ProjectModel deve adicionar via MCP add_kit (Core)"
need crates/vibedeck/src/mcp/tools/resources.rs 'resources::add_kit_items\(&store, &items, ' "MCP add_kit deve chamar add_kit_items"
finish
