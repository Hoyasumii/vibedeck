#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'state.running < limit' "runScripts não confere o contador de scripts em execução contra o limite"
hasF $RE 'concurrency: 2' "o teste deve usar limite 2"
hasF $RE 'two.peak == min(2, cpu)' "o teste deve exigir pico igual ao limite"
finish
