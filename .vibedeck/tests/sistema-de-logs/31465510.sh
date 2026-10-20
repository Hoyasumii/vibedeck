#!/usr/bin/env bash
# Gravações do ProjectModel registram store.file_written com file relativo e undo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/(Logging|ProjectStore)\.swift$|^Sources/VibeDeckApp/ProjectModel\.swift$|^Tests/VibeDeckCoreTests/LoggingTests\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
L=Sources/VibeDeckCore/Logging.swift
body=$(region "$L" 'public static func fileWritten' '^    }$')
printf '%s' "$body" | grep -q 'info("store.file_written"' || bad "$L: fileWritten deve gravar info store.file_written"
printf '%s' "$body" | grep -q '"file": String(url.standardizedFileURL.path.dropFirst(prefix.count))' || bad "$L: context.file deve ser o caminho relativo ao projeto"
printf '%s' "$body" | grep -q '"undo":' || bad "$L: context.undo ausente"
region Sources/VibeDeckCore/ProjectStore.swift 'public enum AtomicFile' '^}$' | grep -q 'VDLog.fileWritten' || bad "AtomicFile.write não chama VDLog.fileWritten"
P=Sources/VibeDeckApp/ProjectModel.swift
# Toda escrita direta do modelo passa por AtomicFile (via write()) ou por ProjectStore, e informa o nome do undo.
grep -q 'VDLog.\$undoName.withValue' "$P" || bad "$P: gravações não definem o nome do undo"
grep -q 'info("store.file_removed"' "$P" || bad "$P: remoção de arquivo não é registrada"
while IFS= read -r hit; do bad "$hit: gravação que não passa por AtomicFile (sem log)"; done < <(grep -nE '\.write\(to:|FileManager\.default\.(createFile|moveItem|copyItem)|try? data\.write|\.write\(to ' "$P" | grep -v 'to: backup' | grep -vF 'try FileManager.default.moveItem(at: backup, to: target)' | sed "s|^|$P:|" || true)
# Restoring a directory preserves its bytes with a move rather than AtomicFile.write.
# This one direct move must log the restored group, project and undo metadata.
restore=$(region "$P" 'private func restoreDirectoryGroup' '^    }$')
if printf '%s' "$restore" | grep -qF 'moveItem(at: backup, to: target)'; then
  printf '%s' "$restore" | grep -q 'info("store.group_restored"' || bad "$P: restauração de grupo sem log"
  printf '%s' "$restore" | grep -q 'project: store.root' || bad "$P: restauração sem projeto no log"
  printf '%s' "$restore" | grep -q '"undo": "Apagar grupo"' || bad "$P: restauração sem nome do undo no log"
fi
[ $fail -eq 0 ] || exit 1
run_tests LoggingTests/editingLogsMetadataWithoutDocumentContent
