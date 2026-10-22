#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Root da janela: conteúdo do WindowGroup (VibeDeckApp.swift/RootView), WelcomeView e ProjectWindow
# não podem impor tamanho mínimo/fixo. minWidth em subviews internas (DocView etc.) é permitido.
pat='\.frame\([^)]*(minWidth|minHeight|idealWidth|idealHeight)|\.windowResizability\(\.contentMinSize\)|\.windowResizability\(\.contentSize\)'
for f in Sources/VibeDeckApp/VibeDeckApp.swift Sources/VibeDeckApp/WelcomeView.swift; do
  while IFS=: read -r n line; do
    case "$line" in *//*) [[ "${line%%//*}" =~ [^[:space:]] ]] || continue ;; esac
    bad "$f:$n" "min-size no root da janela (${line#"${line%%[![:space:]]*}"})"
  done < <(grep -nE "$pat" "$f" || true)
done
# Janela V2 (V2ProjectWindow): o body raiz é trilho + NavigationSplitView; o frame(width:) do sheet é permitido, minWidth/minHeight não.
f=Sources/VibeDeckApp/V2/V2ProjectWindow.swift
[ -f "$f" ] || bad "$f" "janela V2 ausente"
while IFS=: read -r n line; do
  [[ "${line%%//*}" =~ (minWidth|minHeight) ]] || continue
  bad "$f:$n" "minWidth/minHeight na janela V2 raiz"
done < <(grep -nE 'minWidth|minHeight' "$f" || true)
# Raiz: o WindowGroup deve renderizar RootView sem modificador de frame.
awk '/WindowGroup\(/{g=1} g&&/RootView\(root:/{print; exit}' Sources/VibeDeckApp/VibeDeckApp.swift | grep  'RootView(root: \$root)$' >/dev/null \
  || bad Sources/VibeDeckApp/VibeDeckApp.swift "RootView no WindowGroup deveria ficar sem modificadores de frame"
exit $fail
