#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'guard.running < limit' "run_scripts não confere o contador de scripts em execução contra o limite"
hasF $EXEC 'concurrency: Some(2)' "o teste deve usar limite 2"
hasF $EXEC 'c.fetch_add(1, Ordering::SeqCst)' "o runner do teste deve incrementar o contador"
hasF $EXEC 'c.fetch_sub(1, Ordering::SeqCst)' "o runner do teste deve decrementar o contador"
hasF $EXEC 'assert!((2..=2).contains(&observed)' "o teste deve exigir pico igual ao limite"
finish
