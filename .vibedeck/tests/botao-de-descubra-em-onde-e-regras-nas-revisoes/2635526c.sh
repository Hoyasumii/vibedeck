#!/usr/bin/env bash
# Cada sugestão vem com uma justificativa curta (onde encontrou, ex.: arquivo:linha).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# O schema exige reason em fields e rules.
need "$CORE" '"required":\["field","value","reason"\]' "o schema deve exigir reason em cada campo sugerido"
need "$CORE" '"required":\["slug","reason"\]' "o schema deve exigir reason em cada tópico sugerido"
need "$CORE" 'reason: uma frase curta dizendo onde encontrou \(ex\.: [^)]*:[0-9]+\)' "o prompt deve pedir reason com arquivo:linha"
prop=$(body "$CORE" 'public static func proposal\(')
[ "$(printf '%s\n' "$prop" | grep -c 'reason: suggestion.reason')" -ge 2 ] || { echo "$CORE: proposal deve levar a reason para campos e tópicos"; fail=1; }
sheet=$(body "$APP" 'struct ReviewDiscoverSheet')
[ "$(printf '%s\n' "$sheet" | grep -cE 'if let reason = (change|topic)\.reason')" -ge 2 ] || { echo "$APP: a sheet deve mostrar a justificativa de campos e de tópicos"; fail=1; }
finish
run_tests ReviewDiscoverTests/parsesStructuredOutput
