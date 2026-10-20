#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RE 'func sameBuildToolNeverOverlaps' "falta o teste de serialização por ferramenta"
hasF $RE '!peak.overlap("bash .vibedeck/tests/x/a.sh", "bash .vibedeck/tests/x/b.sh")' "o teste deve exigir que a mesma ferramenta não se sobreponha"
hasF $RE 'peak.overlap("bash .vibedeck/tests/x/a.sh", "plain")' "o teste deve exigir que outra ferramenta rode junto"
hasF $PS 'jobs[$0].locks.isDisjoint(with: state.busy)' "runScripts deve só iniciar scripts cujas ferramentas estão livres"
hasF $PS 'state.busy.formUnion(job.locks)' "runScripts deve travar a ferramenta ao iniciar"
finish
