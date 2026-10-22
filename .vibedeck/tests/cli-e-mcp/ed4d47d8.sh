#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/vibedeck/"; then exit 77; fi
python3 -I - <<'PY'
import glob, re, sys
bad = []
args = open("crates/vibedeck/src/mcp/args.rs").read()
m = re.search(r"pub fn list\(.*?\n    }\n", args, re.S)
if not m: bad.append("mcp/args.rs: helper Args::list sumiu")
else:
    for n in ["Value::Array", "serde_json::from_str::<Vec<String>>", "split(',')"]:
        if n not in m.group(0): bad.append(f"Args::list: falta {n}")
for f in glob.glob("crates/vibedeck/src/mcp/tools/*.rs"):
    src = open(f).read()
    for i, l in enumerate(src.split("\n")):
        if re.search(r"split\(','\)|split\(\",\"\)|from_str::<Vec<String>>", l):
            bad.append(f"{f}:{i+1}: parse de lista feito à mão; use args.list(\"chave\")")
    for key in sorted(set(re.findall(r'\.list\("([a-z_]+)"\)', src))):
        if not re.search(r'"%s",\s*"array"|"%s"\s*:\s*\{\s*"type"\s*:\s*"array"|\("%s",\s*json!\(\{\s*"type"\s*:\s*"array"' % (key, key, key), src):
            bad.append(f'{f}: parâmetro de lista "{key}" sem type "array" no schema')
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
