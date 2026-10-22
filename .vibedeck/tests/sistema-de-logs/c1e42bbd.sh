#!/usr/bin/env bash
# Logs fora do projeto, JSONL por dia, em modo append, sem escrita atômica (Core Rust e app).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies "^crates/vibedeck-core/src/project/logs\.rs$|^Sources/VibeDeckApp/Core/Support/Logging\.swift$"
fail=0
bad() { echo "$1"; fail=1; }
R=$RUSTLOG
store=$(region "$R" 'pub struct LogStore' '^}$')
impl=$(awk '/^impl LogStore/ {on=1} on {print} on && /^}$/ {exit}' "$R")
printf '%s' "$impl" | grep -F 'options.append(true)' >/dev/null || bad "$R: LogStore::append deve abrir em modo append"
printf '%s' "$impl" | grep -E 'write_atomic|AtomicFile' >/dev/null && bad "$R: LogStore não pode usar escrita atômica (store::write_atomic)"
printf '%s' "$impl" | grep -F 'Library/Application Support/VibeDeck/logs' >/dev/null || bad "$R: no macOS os logs devem ficar em Application Support/VibeDeck/logs"
printf '%s' "$impl" | grep -F 'vibedeck/logs' >/dev/null || bad "$R: fora do macOS o diretório deve ser <estado>/vibedeck/logs"
printf '%s' "$impl" | grep -F 'format!("{}.jsonl"' >/dev/null || bad "$R: arquivo deve ser <dia>.jsonl"
printf '%s' "$impl" | grep -F 'data.push(b'"'"'\n'"'"')' >/dev/null || bad "$R: cada entrada deve ser uma linha"
A=$APPLOG
app=$(region "$A" 'struct LogStore' '^}$')
printf '%s' "$app" | grep  'O_WRONLY | O_APPEND | O_CREAT' >/dev/null || bad "$A: LogStore.append do app deve abrir com O_APPEND"
printf '%s' "$app" | grep  'AtomicFile' >/dev/null && bad "$A: LogStore do app não pode usar AtomicFile"
printf '%s' "$app" | grep  '\.applicationSupportDirectory' >/dev/null || bad "$A: logs do app devem ficar em Application Support"
[ $fail -eq 0 ] || exit 1
run_tests appends_concorrentes_mantem_linhas_inteiras anexa_e_filtra_mais_novo_primeiro
