#!/usr/bin/env bash
# viável aprova (Core)
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedViableVerdictApprovesEligibleIdeas(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedViableVerdictApprovesEligibleIdeas não passou/ausente"; exit 1; }
