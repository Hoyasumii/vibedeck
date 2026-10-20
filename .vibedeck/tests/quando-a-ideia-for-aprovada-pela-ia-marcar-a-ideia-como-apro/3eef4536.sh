#!/usr/bin/env bash
# ideia promovida preservada
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedViableVerdictPreservesClosedAndPromotedIdeas(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedViableVerdictPreservesClosedAndPromotedIdeas não passou/ausente"; exit 1; }
