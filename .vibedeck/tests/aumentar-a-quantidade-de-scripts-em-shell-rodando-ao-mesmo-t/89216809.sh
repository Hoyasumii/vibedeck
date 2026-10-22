#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'pub fn default_script_concurrency() -> usize {' "falta o limite padrão"
hasF $EXEC 'std::thread::available_parallelism().map_or(1, |n| n.get())' "o padrão deve ser o número de núcleos ativos"
hasF $EXEC 'assert_eq!(script_concurrency(None), cores);' "o teste deve fixar o padrão"
finish
