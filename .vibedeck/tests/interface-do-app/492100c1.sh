#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Boas-vindas e janela V2 (trilho, conteúdo e detalhe) escondem o fundo da toolbar.
for f in Sources/VibeDeckApp/WelcomeView.swift Sources/VibeDeckApp/V2/V2ProjectWindow.swift; do
  grep -qE '^\s*\.toolbarBackgroundVisibility\(\.hidden, for: \.windowToolbar\)' "$f" \
    || bad "$f" "falta .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
done
# V2: a casca (trilho + conteúdo) e a coluna de detalhe declaram o modificador (2 ocorrências na janela).
n=$(grep -cE '^\s*\.toolbarBackgroundVisibility\(\.hidden, for: \.windowToolbar\)' Sources/VibeDeckApp/V2/V2ProjectWindow.swift || true)
[ "$n" -ge 2 ] || bad Sources/VibeDeckApp/V2/V2ProjectWindow.swift "esperado o modificador na casca e no detalhe ($n encontrado)"
exit $fail
