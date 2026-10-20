#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $MODEL 'var lanes = ' "remaining deve distribuir os scripts em faixas paralelas"
hasF $MODEL 'lanes.max()' "remaining deve usar a faixa mais longa, não a soma"
has $APPT 'func remainingEstimateConsidersParallelism' "falta o teste da estimativa com paralelismo"
hasF $APPT 'serial.remaining(at: start) == 40' "o teste deve fixar 40 s no limite 1"
hasF $APPT 'parallel.remaining(at: start) ==' "o teste deve conferir a estimativa paralela"
finish
