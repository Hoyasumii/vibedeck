#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 1470074F: veredito não viável preserva o status (inclusive approved) e grava o readiness.
require_apply
b=$(apply_body)
# A aprovação só ocorre dentro do `if readiness.viable`; fora dele o status não é tocado.
n=$(grep -c 'idea.status =' <<<"$b" || true)
[ "$n" -eq 1 ] || bad "$LOGIC: apply deve atribuir status em um só lugar (achei $n)"
grep -B1 'idea.status = .approved' <<<"$b" | grep -q 'if readiness.viable' || bad "$LOGIC: a atribuição de approved deve ficar sob 'if readiness.viable'"
has_test savedNonviableVerdictPreservesEveryStatus
finish
