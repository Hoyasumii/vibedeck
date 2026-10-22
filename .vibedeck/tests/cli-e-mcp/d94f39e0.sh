#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/vibedeck/"; then exit 77; fi
python3 -I - <<'PY'
import re, sys
bad = []
cli = open("crates/vibedeck/src/cli/ideas.rs").read()
mcp = open("crates/vibedeck/src/mcp/tools/ideas.rs").read()
if not re.search(r"\bUnpromote\s*\{", cli): bad.append("cli/ideas.rs: subcomando ideas unpromote ausente")
if "unpromote_idea(" not in cli: bad.append("cli/ideas.rs: unpromote não chama store.unpromote_idea")
if '"unpromote_idea"' not in mcp: bad.append("mcp: ferramenta unpromote_idea ausente")
if "unpromote_idea(" not in mcp: bad.append("mcp: unpromote_idea não chama store.unpromote_idea")
m = re.search(r'Tool::new\(\s*"unpromote_idea",\s*"((?:[^"\\]|\\.)*)"', mcp)
if not m or "Só faça isso quando o usuário pedir." not in m.group(1):
    bad.append('mcp: descrição de unpromote_idea sem "Só faça isso quando o usuário pedir."')
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
