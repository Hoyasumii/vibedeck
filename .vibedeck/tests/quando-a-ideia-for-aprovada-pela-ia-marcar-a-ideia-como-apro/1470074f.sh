#!/usr/bin/env bash
# não viável preserva status e grava readiness
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedNonviableVerdictPreservesEveryStatus(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedNonviableVerdictPreservesEveryStatus não passou/ausente"; exit 1; }
