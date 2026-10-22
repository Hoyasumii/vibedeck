#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
V=Sources/VibeDeckApp/V2
# V2: um filtro por conceito, no topo da coluna de conteúdo (campo de texto com #tag + chips de tag).
c=$V/V2ContentColumn.swift
for p in 'LoggedTextField\("Filtrar' 'filter\.search' 'VDFilterChip\(title: "#" \+ tag' 'filter\.matches' 'isFiltering'; do
  grep -qE "$p" "$c" || bad "$c" "padrão de filtro ausente: $p"
done
# Regra do filtro: texto livre, tokens #tag digitados e chips, em um único tipo compartilhado.
l=$V/V2ListFilter.swift
for p in 'hasPrefix\("#"\)' 'localizedCaseInsensitiveContains' 'caseInsensitiveCompare' 'func matches\(_ row: SectionRow\)'; do
  grep -qE "$p" "$l" || bad "$l" "padrão de filtro ausente: $p"
done
# A tabela do detalhe (SectionListView) só aplica o filtro da coluna: sem campo próprio (filtro duplicado).
s=Sources/VibeDeckApp/SectionListView.swift
grep -v '^\s*//' "$s" | grep -E '\.searchable\(|TagToken|private var tagBar' >/dev/null && bad "$s" "SectionListView não pode ter filtro próprio (.searchable/tagBar): use o filtro da coluna"
grep -qE '@Binding var filter: V2ListFilter' "$s" || bad "$s" "SectionListView sem o filtro compartilhado (@Binding var filter: V2ListFilter)"
grep -qE 'allRows\.filter \{ filter\.matches' "$s" || bad "$s" "SectionListView não aplica filter.matches"
grep -qE 'TagChips\(tags: row.tags, onTap: toggle\)' "$s" || bad "$s" "chips de tag da tabela não filtram (TagChips onTap: toggle)"
# A janela renderiza seções por SectionListView e compartilha o mesmo filtro com a coluna.
pw=$V/V2ProjectWindow.swift
grep -qE 'SectionListView\(section: section, filter: \$listFilter\)' "$pw" \
  && grep -qE 'V2ContentColumn\(space: space, concept: conceptBinding, selection: \$selection, filter: \$listFilter' "$pw" \
  || bad "$pw" "coluna e SectionListView precisam compartilhar \$listFilter"
grep -qE 'case \.section\(let section\):' "$pw" || bad "$pw" "seções não são renderizadas pelo case genérico .section"
# Nenhuma seção ligada a outra lista própria: .section(.x) só deve cair no case genérico.
while IFS=: read -r n line; do
  bad "$pw:$n" "view de lista própria para uma seção (use SectionListView): ${line#"${line%%[![:space:]]*}"}"
done < <(grep -nE 'case \.section\(\.' "$pw" || true)
exit $fail
