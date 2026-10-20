#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'onEvent(.started(' "runScripts não emite .started"
hasF $PS 'onEvent(.finished(' "runScripts não emite .finished"
before $PS 'onEvent\(\.started\(' 'onEvent\(\.finished\(' ".started deve ser emitido antes do .finished"
hasF $RE '.count == 1' "o teste deve exigir exatamente um .started e um .finished por regra"
hasF $RE 'start! < finish!' "o teste deve exigir started antes de finished"
finish
