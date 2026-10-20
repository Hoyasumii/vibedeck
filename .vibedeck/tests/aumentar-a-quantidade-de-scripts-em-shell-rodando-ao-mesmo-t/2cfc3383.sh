#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'let next = state.pending.firstIndex(where: { jobs[$0].locks.isDisjoint(with: state.busy) })' "esperar a trava não pode ocupar vaga: o próximo candidato deve ser o primeiro com ferramenta livre"
hasF $PS 'state.running += 1' "scripts serializados contam para o limite enquanto rodam"
hasF $RE 'inline = try scripts(store, ["swift test --filter A", "swift test --filter B", "echo free"])' "falta o teste do script sem ferramenta"
hasF $RE 'slots.overlap("swift test --filter A", "echo free")' "o teste deve exigir que o script livre rode com o primeiro swift"
finish
