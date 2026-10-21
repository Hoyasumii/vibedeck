#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
L=.vibedeck/tests/conceitos-do-produto/9e02c127.sh
for f in $MODEL $SETTINGS; do hasF $L "\"$f\"" "$f precisa estar no LOCAL_OK, com justificativa"; done
grep -F "\"$SETTINGS\"" $L | grep  '#' >/dev/null || { echo "$L: $SETTINGS sem justificativa"; bad=1; }
out=$(VIBEDECK_FILES= bash $L 2>&1) || { echo "$L falhou:"; echo "$out"; bad=1; }
finish
