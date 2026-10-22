#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/(vibedeck/|vibedeck-core/src/reviews/)"; then exit 77; fi
python3 -I - <<'PY'
import glob, re, sys
bad = []
core = open("crates/vibedeck-core/src/reviews/mod.rs").read()
if not re.search(r'status\.as_deref\(\) == Some\("done"\) && !change\.force\s*\{\s*gate::ensure_verified\(', core):
    bad.append("reviews/mod.rs: apply_update deve chamar gate::ensure_verified quando status=done e !force")
mcp = open("crates/vibedeck/src/mcp/tools/reviews.rs").read()
if "apply_update(" not in mcp: bad.append("mcp: update_review_item não usa reviews::apply_update")
if not re.search(r"force:\s*false", mcp): bad.append("mcp: update_review_item deve fixar force: false")
for f in glob.glob("crates/vibedeck/src/mcp/**/*.rs", recursive=True):
    if re.search(r'"force"', open(f).read()): bad.append(f"{f}: parâmetro \"force\" no schema MCP")
cli = open("crates/vibedeck/src/cli/reviews.rs").read()
if "apply_update(" not in cli or "force: a.force" not in cli: bad.append("cli/reviews.rs: review set deve usar apply_update com force: a.force")
# nenhum outro caminho grava status Done direto, sem apply_update
for f in glob.glob("crates/vibedeck/src/**/*.rs", recursive=True) + glob.glob("crates/vibedeck-core/src/**/*.rs", recursive=True):
    if f.endswith("reviews/mod.rs") or "/tests" in f: continue
    for i, l in enumerate(open(f).read().split("\n")):
        if re.search(r"\.status\s*=\s*ReviewStatus::Done", l): bad.append(f"{f}:{i+1}: grava ReviewStatus::Done fora de apply_update")
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
