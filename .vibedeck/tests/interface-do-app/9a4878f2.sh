#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Nenhuma view que apresenta .inspector (nem os headers de Idea/ReviewGroup) pode usar ViewThatFits em código (comentários ok).
files=$(grep -lE '\.inspector\(' Sources/VibeDeckApp/*.swift || true)
files="$files Sources/VibeDeckApp/IdeaView.swift Sources/VibeDeckApp/ReviewGroupView.swift"
for f in $(printf '%s\n' $files | sort -u); do
  while IFS=: read -r n line; do
    code="${line%%//*}"
    [[ "$code" == *ViewThatFits* ]] && bad "$f:$n" "ViewThatFits em view com .inspector (use um HStack único)"
  done < <(grep -n 'ViewThatFits' "$f" || true)
done
exit $fail
