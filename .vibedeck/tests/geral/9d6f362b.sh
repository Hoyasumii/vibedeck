#!/usr/bin/env bash
# Checks são só-adição; AGENTS.md só muda junto com AgentsGuide.swift (de onde é regenerado).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
fail=0

# Check já versionado alterado ou removido = edição à mão.
changed=$( { git diff --name-only --diff-filter=MDR HEAD -- .vibedeck/checks 2>/dev/null || true; } | sort -u)
if [ -n "$changed" ]; then
  while IFS= read -r f; do echo "$f: check existente foi alterado/removido (histórico de auditoria)"; done <<< "$changed"
  fail=1
fi

if ! git diff --quiet HEAD -- .vibedeck/AGENTS.md 2>/dev/null; then
  if git diff --quiet HEAD -- Sources/VibeDeckCore/AgentsGuide.swift 2>/dev/null; then
    echo ".vibedeck/AGENTS.md: alterado sem mudança em Sources/VibeDeckCore/AgentsGuide.swift (edite o guia, não o gerado)"
    fail=1
  fi
fi
exit $fail
