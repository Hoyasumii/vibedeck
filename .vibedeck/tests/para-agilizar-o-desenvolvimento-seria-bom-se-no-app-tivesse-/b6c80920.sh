#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
grep -q "IdeaImplementation.prompt(" <<<"$BODY" || fail "$V: copyPromptButton não chama IdeaImplementation.prompt"
grep -E "\"[^\"]*(Implemente a ideia|get_idea|submit_rule_check)" $V >&2 && fail "$V: prompt literal duplicado na View"
exit 0
