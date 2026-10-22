#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# EC979504: o teste da regra de aprovação por avaliação cobre os quatro casos.
has_test savedViableVerdictApprovesEligibleIdeas savedNonviableVerdictPreservesEveryStatus savedViableVerdictPreservesClosedAndPromotedIdeas savedVerdictWithoutRulesDoesNotApprove
grep -q 'Idea' "$TESTS" && grep -q '@testable import VibeDeckApp' "$TESTS" || bad "$TESTS: deve testar o app (@testable import VibeDeckApp)"
finish
