#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# WelcomeView e coluna de detalhe do ProjectWindow escondem o fundo da toolbar.
for f in Sources/VibeDeckApp/WelcomeView.swift Sources/VibeDeckApp/ProjectWindow.swift; do
  grep -qE '^\s*\.toolbarBackgroundVisibility\(\.hidden, for: \.windowToolbar\)' "$f" \
    || bad "$f" "falta .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
done
exit $fail
