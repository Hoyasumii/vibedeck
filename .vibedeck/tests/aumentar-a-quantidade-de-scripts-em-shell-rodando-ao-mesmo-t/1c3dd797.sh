#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'requested.unwrap_or(cores).clamp(1, cores)' "o limite deve ser ajustado a 1..=núcleos"
hasF $EXEC 'assert_eq!(script_concurrency(Some(0)), 1);' "limite 0 deve virar 1"
hasF $EXEC 'assert_eq!(script_concurrency(Some(10_000)), cores);' "limite alto deve virar o número de núcleos"
finish
