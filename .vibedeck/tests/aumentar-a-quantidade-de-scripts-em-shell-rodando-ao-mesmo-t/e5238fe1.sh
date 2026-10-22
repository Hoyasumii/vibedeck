#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $EXEC 'fn same_build_tool_never_overlaps' "falta o teste de serialização por ferramenta"
hasF $EXEC 'assert_eq!(overlap.load(Ordering::SeqCst), 0);' "o teste deve exigir que a mesma ferramenta não se sobreponha"
hasF $EXEC 'assert!(started.elapsed() >= Duration::from_millis(240));' "o teste deve exigir que só as ferramentas diferentes rodem juntas"
hasF $EXEC 'jobs[i].locks.is_disjoint(&guard.busy)' "run_scripts deve só iniciar scripts cujas ferramentas estão livres"
hasF $EXEC 'guard.busy.extend(job.locks.iter().copied());' "run_scripts deve travar a ferramenta ao iniciar"
finish
