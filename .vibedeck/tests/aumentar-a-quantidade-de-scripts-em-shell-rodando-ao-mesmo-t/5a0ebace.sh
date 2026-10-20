#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
before $RT 'try process\.run\(\)' 'timeoutQueue\.asyncAfter' "o timer de timeout deve ser armado depois de process.run()"
[ "$(grep -c 'timeoutQueue.asyncAfter' $RT)" = 1 ] || { echo "$RT: deve haver um único ponto que arma o timer"; bad=1; }
hasF $RT 'timeout: 120' "RuleTestRunner.live deve usar timeout de 120 s"
finish
