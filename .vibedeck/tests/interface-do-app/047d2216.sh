#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
W=Sources/VibeDeckApp/V2/V2ProjectWindow.swift
# V2: coluna de conteúdo min 220 / ideal 260 / max 340 (navigationSplitViewColumnWidth); painel de IA à direita
# como único .inspector da janela, min 300 / ideal 340 / max 460 (inspectorColumnWidth).
grep -qE 'navigationSplitViewColumnWidth\(min: 220, ideal: 260, max: 340\)' "$W" \
  || bad "$W" "coluna de conteúdo sem navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)"
grep -qE 'inspectorColumnWidth\(min: 300, ideal: 340, max: 460\)' "$W" \
  || bad "$W" "painel de IA sem inspectorColumnWidth(min: 300, ideal: 340, max: 460)"
# Nenhuma outra view abre .inspector: o contexto do item mora no detalhe (V2DetailContext, regra 34D2EA32).
for f in $(grep -lE '^\s*\.inspector\(' Sources/VibeDeckApp/*.swift Sources/VibeDeckApp/V2/*.swift Sources/VibeDeckApp/Core/*/*.swift 2>/dev/null || true); do
  [ "$f" = "$W" ] && continue
  bad "$f" ".inspector fora da janela V2: use .detailContext(isPresented:) para o contexto do item"
done
# Todo .inspector declara inspectorColumnWidth.
for f in $(grep -rlE '^\s*\.inspector\(' Sources/VibeDeckApp --include='*.swift' || true); do
  ni=$(grep -cE '^\s*\.inspector\(' "$f" || true)
  nw=$(grep -cE '\.inspectorColumnWidth\(' "$f" || true)
  [ "$nw" -ge "$ni" ] || bad "$f" "$ni .inspector(...) mas só $nw .inspectorColumnWidth(...)"
done
# NavigationSplitView novo precisa do mesmo modificador de largura.
for g in $(grep -rl 'NavigationSplitView' Sources/VibeDeckApp --include='*.swift'); do
  [ "$g" = "$W" ] && continue
  grep -v '^\s*//' "$g" | grep 'NavigationSplitView' >/dev/null || continue
  grep -q 'navigationSplitViewColumnWidth' "$g" || bad "$g" "NavigationSplitView sem navigationSplitViewColumnWidth"
done
# Exceções de largura fixa vêm de DesignTokens (trilho e contexto do item), nunca de número solto na view.
grep -q 'width: DesignTokens.V2Layout.railWidth' Sources/VibeDeckApp/V2/V2Rail.swift \
  || bad Sources/VibeDeckApp/V2/V2Rail.swift "trilho sem a largura fixa de DesignTokens.V2Layout.railWidth"
grep -q 'width: DesignTokens.V2Layout.contextWidth' Sources/VibeDeckApp/V2/V2DetailContext.swift \
  || bad Sources/VibeDeckApp/V2/V2DetailContext.swift "contexto do item sem a largura de DesignTokens.V2Layout.contextWidth"
# Limites de coluna não podem vir de .frame logo após a coluna/inspector da janela.
while IFS=: read -r n line; do
  bad "$W:$n" "largura de coluna controlada por .frame (use inspectorColumnWidth/navigationSplitViewColumnWidth)"
done < <(grep -nE '^\s*\}\s*\.frame\((min|max|ideal)?[Ww]idth' "$W" | grep -E 'inspector|Split' || true)
exit $fail
