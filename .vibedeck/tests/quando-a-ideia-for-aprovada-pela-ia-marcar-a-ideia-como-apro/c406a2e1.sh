#!/usr/bin/env bash
# salvar não promove nem cria tópicos
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedEvaluationDoesNotCreateOrActivateTopics(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedEvaluationDoesNotCreateOrActivateTopics não passou/ausente"; exit 1; }
