#!/usr/bin/env bash
# Checks são só-adição; AGENTS.md/guide.md só mudam junto com a fonte do guia no Core (ai/guide.rs, guide_reference.md, context.rs), de onde são regenerados.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
fail=0
GUIDE_SRC=(crates/vibedeck-core/src/ai/guide.rs crates/vibedeck-core/src/ai/guide_reference.md crates/vibedeck-core/src/ai/context.rs crates/vibedeck-core/src/ai/policy_instructions.txt)

# Check já versionado alterado ou removido = edição à mão.
changed=$( { git diff --name-only --diff-filter=MDR HEAD -- .vibedeck/checks 2>/dev/null || true; } | sort -u)
if [ -n "$changed" ]; then
  while IFS= read -r f; do echo "$f: check existente foi alterado/removido (histórico de auditoria)"; done <<< "$changed"
  fail=1
fi

for gen in .vibedeck/AGENTS.md .vibedeck/guide.md; do
  if ! git diff --quiet HEAD -- "$gen" 2>/dev/null; then
    if git diff --quiet HEAD -- "${GUIDE_SRC[@]}" 2>/dev/null; then
      echo "$gen: alterado sem mudança na fonte do guia (${GUIDE_SRC[0]} / guide_reference.md): edite o guia no Core, não o gerado"
      fail=1
    fi
  fi
done
exit $fail
