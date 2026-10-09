#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Toda view com .inspector declara inspectorColumnWidth (min 260, ideal 300-320, max 420-440);
# o NavigationSplitView do ProjectWindow declara navigationSplitViewColumnWidth(min 200, ideal 240, max 320).
for f in $(grep -lE '\.inspector\(' Sources/VibeDeckApp/*.swift); do
  ni=$(grep -cE '^\s*\.inspector\(' "$f" || true)
  nw=$(grep -cE '\.inspectorColumnWidth\(' "$f" || true)
  [ "$nw" -ge "$ni" ] || bad "$f" "$ni .inspector(...) mas só $nw .inspectorColumnWidth(...)"
  while IFS=: read -r n line; do
    if ! echo "$line" | grep -qE 'inspectorColumnWidth\(min: 260, ideal: (300|310|320), max: (420|430|440)\)'; then
      bad "$f:$n" "inspectorColumnWidth fora de min 260 / ideal 300-320 / max 420-440"
    fi
  done < <(grep -nE 'inspectorColumnWidth\(' "$f" || true)
done
f=Sources/VibeDeckApp/ProjectWindow.swift
grep -qE 'navigationSplitViewColumnWidth\(min: 200, ideal: 240, max: 320\)' "$f" \
  || bad "$f" "sidebar sem navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)"
# NavigationSplitView novo fora do ProjectWindow precisa do mesmo modificador.
for g in $(grep -l 'NavigationSplitView' Sources/VibeDeckApp/*.swift); do
  [ "$g" = "$f" ] && continue
  grep -v '^\s*//' "$g" | grep -q 'NavigationSplitView' || continue
  grep -q 'navigationSplitViewColumnWidth' "$g" || bad "$g" "NavigationSplitView sem navigationSplitViewColumnWidth"
done
# Limites de coluna não podem vir de .frame logo após a coluna/inspector.
while IFS=: read -r file n line; do
  bad "$file:$n" "largura de coluna controlada por .frame (use inspectorColumnWidth/navigationSplitViewColumnWidth)"
done < <(grep -nE '^\s*\}\s*\.frame\((min|max|ideal)?[Ww]idth' Sources/VibeDeckApp/ProjectWindow.swift 2>/dev/null | sed 's/^/Sources\/VibeDeckApp\/ProjectWindow.swift:/' | grep -E 'inspector|Split' || true)
exit $fail
