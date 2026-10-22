#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# C55C68D9: approved por avaliação (sem promotedTopic) não cria tópicos; o guia explica que não é promoção.
require_apply
b=$(apply_body)
grep -qE 'store\.|promoteIdea|RuleTopic' <<<"$b" && bad "$LOGIC: apply só pode alterar a ideia recebida (sem tópicos/promoção)"
has_test savedEvaluationDoesNotPromoteOrTouchRules
for f in .vibedeck/guide.md "$GUIDE"; do
  grep -q 'Isso não é promoção' "$f" || bad "$f: guia não diz que approved por avaliação não é promoção"
done
finish
