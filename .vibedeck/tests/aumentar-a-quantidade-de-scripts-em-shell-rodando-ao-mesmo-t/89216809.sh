#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'static var defaultScriptConcurrency: Int { ProcessInfo.processInfo.activeProcessorCount }' "o padrão deve ser activeProcessorCount"
hasF $RE 'ProjectStore.scriptConcurrency(nil) == cpu' "o teste deve fixar o padrão"
hasF $RE 'byDefault.peak == min(cpu, 8)' "o teste deve medir o pico sem limite explícito"
finish
