#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
V=Sources/VibeDeckApp/IdeaView.swift
fail() { echo "$1" >&2; exit 1; }
# Corpo do copyPromptButton
BODY=$(awk '/private var copyPromptButton/{f=1} f{print NR": "$0} f&&/^    }$/{exit}' $V)
[ -n "$BODY" ] || fail "$V: copyPromptButton não encontrado"
L=$(grep -n "copyPromptButton }" $V | head -1 | cut -d: -f1)
[ -n "$L" ] || fail "$V: ToolbarItem do copyPromptButton não encontrado"
# A linha precisa estar fora de qualquer bloco "if !AIProvider.installed.isEmpty"
S=$({ grep -n "if !AIProvider.installed" $V || true; } | sed -n '1s/:.*//p')
if [ -n "$S" ] && [ "$S" -lt "$L" ]; then
  # fecha o if na primeira linha com 12 espaços + }
  E=$(awk -v s="$S" 'NR>s && /^            }$/{print NR; exit}' $V)
  [ -n "$E" ] && [ "$L" -gt "$E" ] || fail "$V:$L: copyPromptButton está atrás da checagem de provedor"
fi
exit 0
