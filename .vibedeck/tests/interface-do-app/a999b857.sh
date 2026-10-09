#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# SectionListView filtra por texto e #tag (tokens + barra de tags + chips); toda seção passa por ele.
f=Sources/VibeDeckApp/SectionListView.swift
for p in 'searchable\(' 'hasPrefix\("#"\)' 'tagBar' 'TagChips\(tags: row.tags, onTap: toggle\)' 'localizedCaseInsensitiveContains'; do
  grep -qE "$p" "$f" || bad "$f" "padrão de filtro ausente: $p"
done
pw=Sources/VibeDeckApp/ProjectWindow.swift
grep -qE 'case \.section\(let section\):' "$pw" && grep -qE 'SectionListView\(section: section\)' "$pw" \
  || bad "$pw" "seções não são renderizadas por SectionListView"
# Nenhuma seção ligada a outra lista própria: .section(.x) só deve cair no case genérico.
while IFS=: read -r n line; do
  bad "$pw:$n" "view de lista própria para uma seção (use SectionListView): ${line#"${line%%[![:space:]]*}"}"
done < <(grep -nE 'case \.section\(\.' "$pw" || true)
exit $fail
