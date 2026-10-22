#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 6A83084F: a mudança para approved e a gravação do readiness acontecem em uma só mutateIdea (um passo de undo).
python3 -I - <<'PY' || fail=1
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
require_apply
finish
