#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Views não chamam ProjectStore direto para mutar; todo mutate* do ProjectModel registra undo.
verbs='(save[A-Z]\w*|create\w*|delete\w*|write\w*|promote\w*|unpromote\w*|rename\w*|trash\w*|move\w*|append\w*|set[A-Z]\w*)'
for f in Sources/VibeDeckApp/*.swift; do
  case "$f" in */ProjectModel.swift|*/ClaudeSession.swift) continue ;; esac  # ClaudeSession usa ClaudeChatStore/runs
  while IFS=: read -r n line; do
    case "$line" in \ *//*|//*) [[ "${line%%//*}" =~ store\. ]] || continue ;; esac
    bad "$f:$n" "mutação direta no ProjectStore (use ProjectModel.mutate*/helpers com undo): ${line#"${line%%[![:space:]]*}"}"
  done < <(grep -nE "store\.$verbs\(" "$f" || true)
done
python3 -I - <<'PY' || fail=1
import re, sys
src = open("Sources/VibeDeckApp/ProjectModel.swift").read().splitlines()
bad = 0
for i, l in enumerate(src):
    m = re.match(r'\s*func (mutate\w*)\(', l)
    if not m: continue
    depth, body = 0, []
    for j in range(i, len(src)):
        body.append(src[j]); depth += src[j].count("{") - src[j].count("}")
        if depth <= 0 and j > i or (depth == 0 and "{" in src[j]): break
    text = "\n".join(body)
    if "registerUndo" not in text and not re.search(r'\bmutate\w*\(', text[text.index('{'):]):
        print(f"Sources/VibeDeckApp/ProjectModel.swift:{i+1}: {m.group(1)} não registra undo"); bad = 1
sys.exit(bad)
PY
exit $fail
