#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RE 'let lock = NSLock()' "o runner de teste deve proteger o contador com lock"
hasF $RE 'lock.withLock { active += 1; peak = max(peak, active) }' "o runner deve incrementar e registrar o pico"
hasF $RE 'lock.withLock { active -= 1;' "o runner deve decrementar o contador"
hasF $RE 'concurrency: 2' "falta o limite 2"
hasF $RE 'two.peak == min(2, cpu)' "o pico com limite 2 deve ser exatamente 2"
hasF $RE 'for limit in [0, cpu + 10]' "faltam os limites 0 e activeProcessorCount+10"
hasF $RE '(1...cpu).contains(peak.peak)' "o pico deve ficar entre 1 e activeProcessorCount"
finish
