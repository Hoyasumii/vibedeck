#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
grep -q "topic: idea.promotedTopic" <<<"$BODY" || fail "$V: botão não passa idea.promotedTopic"
grep -q "promoteIdea" <<<"$BODY" && fail "$V: botão chama promoteIdea"
exit 0
