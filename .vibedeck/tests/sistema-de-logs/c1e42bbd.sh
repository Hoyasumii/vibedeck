#!/usr/bin/env bash
# Logs fora do projeto (Application Support), JSONL por dia, O_APPEND, sem AtomicFile.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/Logging\.swift$|^Tests/VibeDeckCoreTests/LoggingTests\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
L=Sources/VibeDeckCore/Logging.swift
store=$(region "$L" 'public struct LogStore' '^}$')
printf '%s' "$store" | grep -q 'O_WRONLY | O_APPEND | O_CREAT' || bad "$L: LogStore.append deve abrir com O_APPEND"
printf '%s' "$store" | grep -q 'AtomicFile' && bad "$L: LogStore não pode usar AtomicFile"
printf '%s' "$store" | grep -q '\.applicationSupportDirectory' || bad "$L: logs devem ficar em Application Support"
printf '%s' "$store" | grep -q 'VibeDeck/logs' || bad "$L: diretório deve ser VibeDeck/logs"
printf '%s' "$store" | grep -q '"\\(Self.day(date)).jsonl"' || bad "$L: arquivo deve ser <dia>.jsonl"
printf '%s' "$store" | grep -q 'data.append(0x0A)' || bad "$L: cada entrada deve ser uma linha"
[ $fail -eq 0 ] || exit 1
run_tests LoggingTests/concurrentAppendsKeepWholeLines LoggingTests/appendsAndFiltersNewestFirst
