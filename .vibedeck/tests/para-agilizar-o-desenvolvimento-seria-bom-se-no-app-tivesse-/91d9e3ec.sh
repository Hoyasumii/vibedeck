#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
grep -q "LoggedButton" <<<"$BODY" || fail "$V: não usa LoggedButton"
grep -Eq "\.loggedControl\(control: \"[a-z_.0-9]+\", label: \"[^\"]+\"\)" <<<"$BODY" || fail "$V: loggedControl(control:label:) estável ausente"
grep -E "loggedControl\(.*(prompt\)|\\\\\()" <<<"$BODY" >&2 && fail "$V: log inclui conteúdo do prompt"
exit 0
