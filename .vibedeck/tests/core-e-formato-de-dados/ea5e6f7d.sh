#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Erros de usuário via enums thiserror (Error, RuleError, DocError...) com #[error("...")] em português; sem panic!/todo! no Core.
applies '(^|/)crates/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
pat = re.compile(r'\bpanic!\(|\btodo!\(|\bunimplemented!\(')
EN = set("the and to of is are for with from or an in on not this that be it as at by will can has have if when your you could found invalid failed".split())
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f: continue
    s = open(f).read()
    if "#[cfg(test)]" in s: s = s[:s.find("#[cfg(test)]")]
    for n, l in enumerate(s.split("\n"), 1):
        if pat.search(l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: use um case do enum de erro com mensagem em português (não panic!/todo!): {l.strip()}"); bad += 1
    for m in re.finditer(r'#\[error\(\s*"((?:[^"\\]|\\.)*)"', s):
        lit = m.group(1)
        words = set(re.findall(r"[a-z]+", re.sub(r'\{[^}]*\}', ' ', lit).lower()))
        if len(words & EN) >= 2:
            print(f"{f}: mensagem de erro parece inglês: {lit}"); bad += 1
sys.exit(1 if bad else 0)
PY
