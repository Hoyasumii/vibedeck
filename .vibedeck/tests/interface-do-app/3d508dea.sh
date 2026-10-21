#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# CommitTextField edita rascunho e confirma no Return/blur; ReviewGroupView e o editor de tags (LinksView) o usam.
rg=Sources/VibeDeckApp/ReviewGroupView.swift
body=$(awk '/^struct CommitTextField/{p=1} p{print} p&&/^}/{exit}' "$rg")
echo "$body" | grep  '\.onSubmit(submit)' >/dev/null || bad "$rg" "CommitTextField sem confirmação no Return"
echo "$body" | grep  'onChange(of: focused)' >/dev/null || bad "$rg" "CommitTextField sem confirmação ao perder o foco"
echo "$body" | grep  'text: \$draft' >/dev/null || bad "$rg" "CommitTextField não edita um rascunho local"
grep -q 'CommitTextField(' Sources/VibeDeckApp/LinksView.swift || bad Sources/VibeDeckApp/LinksView.swift "editor de tags não usa CommitTextField"
# TextField em ReviewGroupView só com rascunho local ($draft/$newTitle), nunca ligado direto ao modelo.
while IFS=: read -r n line; do
  echo "$line" | grep -E 'text: \$(draft|newTitle)' >/dev/null || bad "$rg:$n" "TextField ligado direto ao modelo (use CommitTextField): ${line#"${line%%[![:space:]]*}"}"
done < <(grep -nE '^\s*(Text|Secure)?Field\(|TextField\(' "$rg" | grep -v 'struct CommitTextField' | grep -vE 'CommitTextField\(' || true)
exit $fail
