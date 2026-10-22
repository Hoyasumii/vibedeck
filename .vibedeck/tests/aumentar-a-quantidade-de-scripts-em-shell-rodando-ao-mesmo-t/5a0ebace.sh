#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
before $RUN 'cmd\.spawn\(\)' 'let started = Instant::now\(\)' "o relógio do timeout deve ser armado depois do spawn do processo"
[ "$(sed '/#\[cfg(test)\]/,$d' $RUN | grep -c 'let started = Instant::now()')" = 1 ] || { echo "$RUN: deve haver um único ponto que arma o relógio do timeout"; bad=1; }
hasF $RUN 'now.duration_since(started) >= opts.timeout' "o timeout deve contar a partir de started"
hasF $EXEC 'Self::live_with(Duration::from_secs(120), 4000)' "RuleTestRunner::live deve usar timeout de 120 s"
finish
