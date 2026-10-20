#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
for fn in createAgent createCommand createSkill createWorkflow; do
  body=$(awk -v f="func $fn" 'index($0,f){p=1} p{print} p&&/^    }$/{exit}' Sources/VibeDeckCore/ProjectStore.swift)
  { printf '%s' "$body" | grep 'uniqueSlug(' >/dev/null && printf '%s' "$body" | grep 'Slug\.make(' >/dev/null; } || { echo "ProjectStore: $fn sem Slug.make + uniqueSlug"; fail=1; }
done
forbid "$INST" 'saveAgent|saveCommand|saveSkill|saveWorkflow' "instalação deve usar apenas as operações create*"
need "$CORET" 'new\.slug == old\.slug \+ "-2"' "teste de slug distinto ausente"
need "$CORET" 'before' "teste de preservação do conteúdo ausente"
finish
