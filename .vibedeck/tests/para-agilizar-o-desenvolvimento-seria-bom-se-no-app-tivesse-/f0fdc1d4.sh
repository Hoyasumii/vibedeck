#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
grep -q "clearContents()" <<<"$BODY" || fail "$V: falta clearContents()"
grep -q "NSPasteboard.general.setString(.*forType: .string)" <<<"$BODY" || fail "$V: falta setString(.string) em NSPasteboard.general"
if grep -E "model\.|AtomicFile|\.write\(" <<<"$BODY" >&2; then fail "$V: handler do botão escreve/altera estado"; fi
exit 0
