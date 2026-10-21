#!/usr/bin/env bash
# Campos de texto registram só a confirmação (Return ou perda de foco), nunca uma entrada por tecla.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/'
fail=0
bad() { echo "$1"; fail=1; }
C=Sources/VibeDeckApp/LoggedControls.swift
fld=$(region "$C" 'struct LoggedTextField' '^}$')
[ "$(printf '%s\n' "$fld" | grep -c 'withAction(')" = 1 ] || bad "$C: LoggedTextField deve chamar withAction em um só lugar (confirm)"
printf '%s' "$fld" | grep  '\.onSubmit { confirm(submitting: true) }' >/dev/null || bad "$C: confirmação por Return ausente"
printf '%s' "$fld" | grep  'onChange(of: focused)' >/dev/null || bad "$C: confirmação por perda de foco ausente"
printf '%s' "$fld" | grep  'VDLog.\$actionID.withValue(id)' >/dev/null || bad "$C: o setter do campo não deve chamar withAction (só carregar o id)"
# TextField/TextEditor cru não pode usar .logging (que logaria a cada tecla).
while IFS= read -r hit; do bad "$hit: TextField/TextEditor com .logging(...) registraria cada tecla"; done < <(grep -rnE '(TextField|TextEditor)\(.*\.logging\(' Sources/VibeDeckApp --include='*.swift' || true)
sub=$(region "$C" 'private struct LoggedSubmit' '^}$')
printf '%s' "$sub" | grep  'onSubmit' >/dev/null || bad "$C: LoggedSubmit deve confirmar no Return"
# O NativeActionLogging exclui seletores de digitação.
grep -q 'typing selectors are deliberately excluded' Sources/VibeDeckApp/NativeActionLogging.swift || bad "NativeActionLogging.swift: seletores de digitação devem ficar de fora"
for sel in insertText deleteBackward insertNewline; do grep -q "\"$sel" Sources/VibeDeckApp/NativeActionLogging.swift && bad "NativeActionLogging.swift: '$sel' não pode estar na lista de ações"; done
[ $fail -eq 0 ] || exit 1
