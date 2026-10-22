#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'std::thread::available_parallelism().map_or(1, |n| n.get())' "o limite padrão deve ser o número de núcleos ativos"
hasF $EXEC 'requested.unwrap_or(cores).clamp(1, cores)' "o limite deve ficar entre 1 e o número de núcleos"
hasF $EXEC 'guard.running < limit' "run_scripts deve respeitar o limite"
has $EXEC 'fn runs_in_parallel_up_to_the_limit' "falta o teste de paralelismo no Core"
hasF $EXEC 'p.fetch_max(now, Ordering::SeqCst)' "o teste deve registrar o pico de execuções simultâneas"
hasF $EXEC 'assert!((2..=2).contains(&observed)' "o teste deve exigir pico > 1 dentro do limite"
finish
