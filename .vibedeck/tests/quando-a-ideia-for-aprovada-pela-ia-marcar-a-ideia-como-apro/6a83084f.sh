#!/usr/bin/env bash
# um único mutateIdea em applyVerdict
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
python3 -I - <<'PY'
import re,sys
f="Sources/VibeDeckApp/IdeaView.swift"
s=open(f).read()
i=s.index("applyVerdict: {")
j=s.index("\n            }", i)
blk=s[i:j]
n=blk.count("model.mutateIdea")
if n!=1 or "verdict.apply(to: &$0)" not in blk:
    print(f"{f}: applyVerdict deve ter exatamente 1 mutateIdea com verdict.apply (achou {n})"); sys.exit(1)
if re.search(r"\.status\s*=", blk):
    print(f"{f}: applyVerdict atribui status diretamente"); sys.exit(1)
PY
