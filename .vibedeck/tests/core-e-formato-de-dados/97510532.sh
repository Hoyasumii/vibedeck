#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Roda a suíte inteira do Core (scripts/test.sh: só VibeDeckCoreTests, funciona só com CLT).
applies '(^|/)(Sources/VibeDeckCore/|Tests/VibeDeckCoreTests/|Package\.swift)'
if ! out=$(scripts/test.sh 2>&1); then
  printf '%s\n' "$out" | grep -E "✘|error:|failed|Issue" | head -30
  printf '%s\n' "$out" | tail -15
  exit 1
fi
printf '%s\n' "$out" | grep -E 'Test run with' | tail -3
