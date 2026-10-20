#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'static var defaultScriptConcurrency: Int { ProcessInfo.processInfo.activeProcessorCount }' "o limite padrão deve ser activeProcessorCount"
hasF $PS 'min(max(requested ?? defaultScriptConcurrency, 1), defaultScriptConcurrency)' "o limite deve ficar entre 1 e activeProcessorCount"
hasF $PS 'state.running < limit' "runScripts deve respeitar o limite"
has $RE 'func runsInParallelUpToTheLimit' "falta o teste de paralelismo no Core"
hasF $RE 'byDefault.peak > 1' "o teste deve exigir pico > 1"
hasF $RE 'byDefault.peak == min(cpu, 8)' "o teste deve limitar o pico por activeProcessorCount"
finish
