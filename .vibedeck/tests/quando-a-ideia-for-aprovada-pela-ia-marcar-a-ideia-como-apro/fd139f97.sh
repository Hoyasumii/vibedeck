#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# FD139F97: discarded/done nunca mudam de status ao salvar a avaliação.
require_apply
grep -qE 'var isClosed: Bool \{ self == \.discarded \|\| self == \.done \}' "$RULES" || bad "$RULES: IdeaStatus.isClosed deve ser discarded || done"
has_test savedViableVerdictPreservesClosedAndPromotedIdeas
finish
