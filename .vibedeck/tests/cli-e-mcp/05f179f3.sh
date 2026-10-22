#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/(vibedeck/|vibedeck-core/src/ai/(mcp_install|usage)\.rs)"; then exit 77; fi
fail() { echo "$1" >&2; exit 1; }
USAGE=crates/vibedeck-core/src/ai/usage.rs; INST=crates/vibedeck-core/src/ai/mcp_install.rs; CLI=crates/vibedeck/src/cli/ai.rs
python3 -I - "$USAGE" "$INST" "$CLI" <<'PY'
import re, sys
usage, inst, cli = (open(p).read() for p in sys.argv[1:4])
bad = []
m = re.search(r"pub fn vibedeck_executable_path\(\).*?\n}\n", usage, re.S)
if not m:
    bad.append("usage.rs: vibedeck_executable_path sumiu")
else:
    f = m.group(0)
    for p in ['env::var("PATH")', "is_file()", "current_exe()"]:
        if p not in f: bad.append(f"vibedeck_executable_path perdeu: {p}")
    if 'env::var("PATH")' in f and "current_exe()" in f and f.index('env::var("PATH")') > f.index("current_exe()"):
        bad.append("o binário atual deve ser só o fallback, depois do PATH")
if not re.search(r'scope == Scope::Project\s*\{\s*"vibedeck"\s*\}\s*else\s*\{\s*cli\s*\}', inst):
    bad.append('mcp_install.rs: escopo project deve registrar o comando "vibedeck" do PATH, não caminho absoluto')
if "usage::vibedeck_executable_path()" not in cli:
    bad.append("cli/ai.rs: mcp install deve registrar usage::vibedeck_executable_path()")
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
