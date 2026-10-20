#!/usr/bin/env bash
# Registrar ações nunca bloqueia a UI: log assíncrono por padrão; sync só em crash/saída.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/|^Sources/VibeDeckCore/Logging\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
L=Sources/VibeDeckCore/Logging.swift
grep -q 'sync: Bool = false' "$L" || bad "$L: VDLog.log deve ter sync=false por padrão"
grep -q 'queue.async(execute: work)' "$L" || bad "$L: caminho assíncrono ausente"
# sync: true só no handler de exceção não tratada.
while IFS=: read -r f n rest; do
  ctx=$(sed -n "$((n-4)),${n}p" "$f")
  printf '%s' "$ctx" | grep -qE 'crash|uncaught_exception|NSSetUncaughtExceptionHandler' || bad "$f:$n: sync: true fora de handler de crash/saída"
done < <(grep -rn 'sync: true' Sources/VibeDeckApp --include='*.swift' || true)
# flush() bloqueia: só ao encerrar o processo.
while IFS=: read -r f n rest; do
  sed -n "$((n-4)),${n}p" "$f" | grep -q 'applicationWillTerminate' || bad "$f:$n: VDLog.flush() bloqueante fora de applicationWillTerminate"
done < <(grep -rn 'VDLog\.flush()' Sources/VibeDeckApp --include='*.swift' || true)
[ $fail -eq 0 ] || exit 1
