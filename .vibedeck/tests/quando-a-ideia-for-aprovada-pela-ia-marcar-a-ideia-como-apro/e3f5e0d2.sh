#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# E3F5E0D2: viável em new/exploring vira approved; approved continua approved.
require_apply
has_test savedViableVerdictApprovesEligibleIdeas
grep -qE 'for status in \[IdeaStatus\.new, \.exploring, \.approved\]' "$TESTS" || bad "$TESTS: o teste deve cobrir new, exploring e approved"
finish
