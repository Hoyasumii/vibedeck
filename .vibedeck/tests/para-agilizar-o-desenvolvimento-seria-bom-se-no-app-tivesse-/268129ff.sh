#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
F=$(grep -n "flush()" <<<"$BODY" | head -1 | cut -d: -f1 | sed "s/:.*//")
P=$(grep -n "IdeaImplementation.prompt" <<<"$BODY" | head -1 | sed "s/:.*//")
[ -n "$F" ] || fail "$V: handler não chama flush()"
[ "$F" -lt "$P" ] || fail "$V: flush() deve vir antes de montar o prompt"
exit 0
