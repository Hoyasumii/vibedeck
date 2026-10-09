#!/usr/bin/env bash
# O último commit termina com Co-Authored-By: Claude ... <noreply@anthropic.com> e tem título curto.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
git rev-parse --verify HEAD >/dev/null 2>&1 || exit 77

msg=$(git log -1 --format=%B)
last=$(printf '%s\n' "$msg" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -1)
title=$(printf '%s\n' "$msg" | head -1)
fail=0

if ! printf '%s\n' "$last" | grep -Eq '^Co-Authored-By: Claude .*<noreply@anthropic\.com>$'; then
  echo "último commit ($(git log -1 --format=%h)): última linha deve ser 'Co-Authored-By: Claude ... <noreply@anthropic.com>', veio: $last"
  fail=1
fi
if [ "${#title}" -gt 72 ]; then
  echo "último commit: título com ${#title} caracteres (máx. 72): $title"
  fail=1
fi
exit $fail
