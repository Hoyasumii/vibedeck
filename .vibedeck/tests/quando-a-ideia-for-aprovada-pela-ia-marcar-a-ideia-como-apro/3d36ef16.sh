#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 3D36EF16: não viável, ou viável em ideia sem regras, não marca a ideia como approved.
require_apply
has_test savedNonviableVerdictPreservesEveryStatus savedVerdictWithoutRulesDoesNotApprove
finish
