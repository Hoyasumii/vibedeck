#!/usr/bin/env bash
# Ações trazem context["control"] estável (não localizado) e context["label"].
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies "$LOG_SCOPE"
fail=0
bad() { echo "$1"; fail=1; }
L=Sources/VibeDeckCore/Logging.swift
grep -q 'context: \["control": control, "label": label\]' "$L" || bad "$L: withAction deve gravar context control e label"
grep -q 'public var control: String? { context\["control"\] }' "$L" || bad "$L: LogEntry.control ausente"
# Ids de controle: estáveis, ASCII minúsculo com . e _ ; nunca vazios.
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -E 's/.*control: "([^"]*)".*/\1/')
  [[ "$id" =~ ^[a-z0-9_.]+$ ]] || bad "${line%%:*}: id de controle inválido ou vazio: '$id' (use ^[a-z0-9_.]+\$)"
done < <(grep -rnoE 'control: "[^"]*"' Sources/VibeDeckApp --include='*.swift' | sed -E 's/^([^:]+:[0-9]+):(.*)$/\1: \2/' || true)
# Todo LoggedButton/LoggedTextField declara seu id no ponto de uso (.loggedControl/.loggedField): contagem por arquivo.
for f in Sources/VibeDeckApp/*.swift; do
  [ "$f" = Sources/VibeDeckApp/LoggedControls.swift ] && continue
  b=$({ grep -oE 'LoggedButton[ (<{]' "$f" || true; } | wc -l | tr -d ' '); c=$({ grep -oE '\.loggedControl\(' "$f" || true; } | wc -l | tr -d ' ')
  [ "$c" -ge "$b" ] || bad "$f: $b LoggedButton mas só $c .loggedControl (controle sem id estável)"
  t=$({ grep -oE 'LoggedTextField\(' "$f" || true; } | wc -l | tr -d ' '); u=$({ grep -oE '\.loggedField\(' "$f" || true; } | wc -l | tr -d ' ')
  [ "$u" -ge "$t" ] || bad "$f: $t LoggedTextField mas só $u .loggedField"
done
[ $fail -eq 0 ] || exit 1
run_tests LoggingTests/actionMetadataRoundTripsAndDecodesOlderEntries
