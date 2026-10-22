#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# C7BD826F: salvar a avaliação com veredito viável marca a ideia (new/exploring) como approved.
require_apply
has_test savedViableVerdictApprovesEligibleIdeas
grep -q 'verdict.apply(to: &' "$IDEAV" || bad "$IDEAV: Salvar avaliação deve aplicar verdict.apply(to:)"
finish
