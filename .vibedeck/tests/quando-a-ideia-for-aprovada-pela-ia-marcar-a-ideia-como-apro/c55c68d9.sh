#!/usr/bin/env bash
# approved por avaliação não cria tópicos
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
out=$(swift test --filter RuleDiscoverTests 2>&1) || { echo "$out" | tail -30; echo "swift test falhou"; exit 1; }
echo "$out" | grep -E 'Test savedEvaluationDoesNotCreateOrActivateTopics(\(\))?.* passed' >/dev/null || { echo "Tests/VibeDeckCoreTests/RuleDiscoverTests.swift: teste savedEvaluationDoesNotCreateOrActivateTopics não passou/ausente"; exit 1; }
for f in .vibedeck/guide.md Sources/VibeDeckCore/AgentsGuide.swift; do
  grep -q 'Isso não é promoção' "$f" || { echo "$f: guia não diz que approved por avaliação não é promoção"; exit 1; }
done
