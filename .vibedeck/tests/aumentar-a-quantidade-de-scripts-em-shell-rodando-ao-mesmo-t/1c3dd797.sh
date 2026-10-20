#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'min(max(requested ?? defaultScriptConcurrency, 1), defaultScriptConcurrency)' "o limite deve ser ajustado a 1...activeProcessorCount"
hasF $RE 'for limit in [0, cpu + 10]' "o teste deve cobrir 0 e activeProcessorCount+10"
hasF $RE '(1...cpu).contains(peak.peak)' "o teste deve exigir pico entre 1 e activeProcessorCount"
hasF $RE 'ProjectStore.scriptConcurrency(0) == 1' "limite 0 deve virar 1"
hasF $RE 'ProjectStore.scriptConcurrency(cpu + 10) == cpu' "limite alto deve virar activeProcessorCount"
finish
