#!/usr/bin/env bash
set -euo pipefail
# Cada sugestão vem com uma justificativa curta (onde encontrou, ex.: arquivo:linha).
source "$(dirname "$0")/_lib.sh"
applies
# O schema exige reason em fields e rules (app e Core Rust).
for f in "$CORE" "$RS"; do
  need "$f" '"required":\["field","value","reason"\]' "o schema deve exigir reason em cada campo sugerido"
  need "$f" '"required":\["slug","reason"\]' "o schema deve exigir reason em cada tópico sugerido"
done
need "$CORE" 'reason: uma frase curta dizendo onde encontrou \(ex\.: [^)]*:[0-9]+\)' "o prompt deve pedir reason com arquivo:linha"
need "$RS" 'reason: uma frase curta dizendo onde encontrou \(ex\.: [^)]*:[0-9]+\)' "o prompt do Core deve pedir reason com arquivo:linha"
prop=$(body "$CORE" 'static func proposal\(')
[ "$(printf '%s\n' "$prop" | grep -c 'reason: suggestion.reason')" -ge 2 ] || { echo "$CORE: proposal deve levar a reason para campos e tópicos"; fail=1; }
rp=$(body "$RS" '^pub fn proposal\(')
[ "$(printf '%s\n' "$rp" | grep -c 'reason: s.reason.clone()')" -ge 2 ] || { echo "$RS: proposal deve levar a reason para campos e tópicos"; fail=1; }
sheet=$(body "$APP" 'struct ReviewDiscoverSheet')
[ "$(printf '%s\n' "$sheet" | grep -cE 'if let reason = (change|topic)\.reason')" -ge 2 ] || { echo "$APP: a sheet deve mostrar a justificativa de campos e de tópicos"; fail=1; }
# A resposta sem justificativa é recusada (uma recuperação na mesma operação).
grep -q 'trimmingCharacters(in: .whitespacesAndNewlines).isEmpty' "$APP" || { echo "$APP: resposta sem reason deve ser tratada como inválida"; fail=1; }
rtest saida_estruturada
finish
