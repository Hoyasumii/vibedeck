#!/usr/bin/env bash
# quatro casos cobertos
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedViableVerdictApprovesEligibleIdeas(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedViableVerdictApprovesEligibleIdeas não passou/ausente"; exit 1; }
echo "$out" | grep -E 'Test savedNonviableVerdictPreservesEveryStatus(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedNonviableVerdictPreservesEveryStatus não passou/ausente"; exit 1; }
echo "$out" | grep -E 'Test savedViableVerdictPreservesClosedAndPromotedIdeas(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedViableVerdictPreservesClosedAndPromotedIdeas não passou/ausente"; exit 1; }
echo "$out" | grep -E 'Test savedVerdictWithoutRulesDoesNotApprove(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedVerdictWithoutRulesDoesNotApprove não passou/ausente"; exit 1; }
