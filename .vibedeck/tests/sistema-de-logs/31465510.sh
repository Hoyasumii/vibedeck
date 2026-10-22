#!/usr/bin/env bash
# Gravações de dados do projeto registram store.file_written com file relativo e undo: no app (AtomicFile) e no Core Rust (store::write_atomic).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies "^crates/vibedeck-core/src/(store|project/logs)\.rs$|^Sources/VibeDeckApp/(ProjectModel\.swift|Core/Support/(Logging|FileUtilities)\.swift)$"
fail=0
bad() { echo "$1"; fail=1; }
L=$APPLOG
body=$(region "$L" 'static func fileWritten' '^    }$')
printf '%s' "$body" | grep  'info("store.file_written"' >/dev/null || bad "$L: fileWritten deve gravar info store.file_written"
printf '%s' "$body" | grep  '"file": String(url.standardizedFileURL.path.dropFirst(prefix.count))' >/dev/null || bad "$L: context.file deve ser o caminho relativo ao projeto"
printf '%s' "$body" | grep  '"undo":' >/dev/null || bad "$L: context.undo ausente"
region Sources/VibeDeckApp/Core/Support/FileUtilities.swift 'enum AtomicFile' '^}$' | grep  'VDLog.fileWritten' >/dev/null || bad "AtomicFile.write (app) não chama VDLog.fileWritten"
P=Sources/VibeDeckApp/ProjectModel.swift
# O ProjectModel não grava arquivos por conta própria: tudo passa pelo Core (MCP) ou por AtomicFile (com log).
while IFS= read -r hit; do bad "$hit: gravação direta que não passa por AtomicFile nem pelo Core (sem log)"; done < <(grep -nE '\.write\(to:|FileManager\.default\.(createFile|moveItem|copyItem)|try\? data\.write|\.write\(to ' "$P" | sed "s|^|$P:|" || true)
# Core Rust: a gravação atômica de registros emite store.file_written (arquivo relativo + undo).
S=crates/vibedeck-core/src/store.rs
if ! region "$S" 'pub fn write_atomic' '^}$' | grep -q 'store\.file_written'; then
  bad "$S: write_atomic não registra store.file_written (o Core Rust grava sem log; logs::info nunca é chamado fora de logs.rs)"
fi
[ $fail -eq 0 ] || exit 1
