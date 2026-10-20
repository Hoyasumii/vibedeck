#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
grep -q "Copiar prompt" <<<"$BODY" || fail "$V: rótulo \"Copiar prompt\" ausente"
grep -q "\"Copiado\"" <<<"$BODY" || fail "$V: feedback \"Copiado\" ausente"
grep -q "\.help(\"" <<<"$BODY" || fail "$V: .help ausente"
exit 0
