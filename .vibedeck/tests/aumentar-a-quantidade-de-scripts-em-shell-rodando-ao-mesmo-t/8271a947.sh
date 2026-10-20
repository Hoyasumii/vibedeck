#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $MODEL 'let start = steps.first(where: { $0.id == ids.first })?.started' "finish() deve usar o started do próprio passo"
hasF $MODEL 'timings.record(now.timeIntervalSince(start), key: job.key)' "a duração gravada deve vir do started do passo"
hasF $APPT 'parallel.steps[1].ended!.timeIntervalSince(parallel.steps[1].started!) == 2' "falta o teste de duração própria do passo"
finish
