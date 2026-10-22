#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 3EEF4536: ideia já promovida (promotedTopic preenchido) mantém status e promotedTopic.
require_apply
b=$(apply_body)
grep -qE 'promotedTopic[[:space:]]*=[^=]' <<<"$b" && bad "$LOGIC: apply não pode alterar promotedTopic"
has_test savedViableVerdictPreservesClosedAndPromotedIdeas
finish
