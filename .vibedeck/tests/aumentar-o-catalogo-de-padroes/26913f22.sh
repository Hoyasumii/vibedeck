#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
b=$(body "$VIEW" 'private struct PatternPicker')
[ -n "$b" ] || { echo "$VIEW: PatternPicker não encontrado"; exit 1; }
printf '%s' "$b" | grep -E 'ForEach\(PatternCategory\.all\.filter' >/dev/null || { echo "$VIEW: ForEach de categorias do PatternPicker não usa PatternCategory.all.filter"; fail=1; }
printf '%s' "$b" | grep -E 'entries\.contains \{ *\$0\.category == category' >/dev/null || { echo "$VIEW: categorias sem templates não são filtradas"; fail=1; }
if hits=$(printf '%s' "$b" | grep -nE '\["(practices|architecture|domain|design|custom)"'); then echo "$VIEW: array literal de categorias no PatternPicker: $hits"; fail=1; fi
finish
