#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
for fn in createAgent createCommand createSkill createWorkflow; do
  need "$INST" "$fn\(" "addKitItems deve usar $fn"
done
forbid "$INST" 'FileManager|\.write\(|createFile|Data\(.*\)\.write' "instalação não deve escrever arquivos diretamente"
forbid "$CAT" 'FileManager|\.write\(' "catálogo não deve escrever arquivos"
for fn in saveAgent saveCommand saveSkill saveWorkflow; do
  grep -n "func $fn" -A6 Sources/VibeDeckCore/*.swift | grep 'AtomicFile.write' >/dev/null || { echo "ProjectStore: $fn não grava via AtomicFile.write"; fail=1; }
done
need "$PMODEL" 'store\.addKitItems' "ProjectModel deve adicionar via store.addKitItems"
finish
