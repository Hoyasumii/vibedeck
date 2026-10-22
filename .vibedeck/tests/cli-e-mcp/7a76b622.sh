#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/vibedeck/"; then exit 77; fi
python3 -I - <<'PY'
import glob, re, sys
bad = []
src = open("crates/vibedeck/src/mcp/tools/ideas.rs").read()
m = re.search(r'Tool::new\(\s*"promote_idea",\s*"((?:[^"\\]|\\.)*)"', src)
if not m or "Só faça isso quando o usuário pedir." not in m.group(1):
    bad.append('mcp: descrição de promote_idea sem "Só faça isso quando o usuário pedir."')
n = 0
for f in glob.glob("crates/vibedeck/src/**/*.rs", recursive=True):
    for i, l in enumerate(open(f).read().split("\n")):
        if re.search(r"(?<!un)\bpromote_idea\(", l):
            n += 1
if n != 2: bad.append(f"promote_idea( chamado {n}x pelo MCP/CLI (esperado: 1 no MCP e 1 no CLI)")
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
