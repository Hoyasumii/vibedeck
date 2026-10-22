#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'let current = Arc::new(AtomicUsize::new(0));' "o runner de teste deve usar um contador atômico"
hasF $EXEC 'p.fetch_max(now, Ordering::SeqCst);' "o runner deve registrar o pico"
hasF $EXEC 'c.fetch_sub(1, Ordering::SeqCst);' "o runner deve decrementar o contador"
hasF $EXEC 'concurrency: Some(2)' "falta o limite 2"
hasF $EXEC 'assert!((2..=2).contains(&observed)' "o pico com limite 2 deve ser exatamente 2"
hasF $EXEC 'assert_eq!(script_concurrency(Some(0)), 1);' "falta o limite 0"
hasF $EXEC 'assert_eq!(script_concurrency(Some(10_000)), cores);' "falta o limite acima do número de núcleos"
finish
