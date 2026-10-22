#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC '.position(|&i| jobs[i].locks.is_disjoint(&guard.busy))' "esperar a trava não pode ocupar vaga: o próximo candidato deve ser o primeiro com ferramenta livre"
hasF $EXEC 'guard.running += 1;' "scripts serializados contam para o limite enquanto rodam"
hasF $EXEC 'if guard.running < limit {' "a vaga só é usada por scripts que vão rodar"
hasF $EXEC 'script_rule("c", "npm test c")' "falta o script de outra ferramenta no teste"
hasF $EXEC 'assert!(started.elapsed() >= Duration::from_millis(240));' "o teste deve medir que só a ferramenta repetida é serializada"
finish
