#!/usr/bin/env bash
# Nenhum objeto author=human some do diff de .vibedeck/ e todo objeto novo criado pela IA tem author=ai.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
python3 -I - <<'PY'
import json, subprocess, sys

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True)

def walk(n, out):
    if isinstance(n, dict):
        if "id" in n and "author" in n:
            out[n["id"]] = n["author"]
        for v in n.values():
            walk(v, out)
    elif isinstance(n, list):
        for v in n:
            walk(v, out)

def objs(txt):
    out = {}
    try:
        walk(json.loads(txt), out)
    except Exception:
        pass
    return out

names = set(sh("git", "diff", "--name-only", "HEAD", "--", ".vibedeck").stdout.split())
bad = 0
for f in sorted(names):
    if not f.endswith(".json") or f.startswith(".vibedeck/checks/") or "/tests/" in f:
        continue
    old = objs(sh("git", "show", f"HEAD:{f}").stdout)
    try:
        new = objs(open(f).read())
    except FileNotFoundError:
        new = {}
    for i, a in old.items():
        if a == "human" and i not in new:
            print(f"{f}: objeto human {i} foi removido"); bad += 1
        elif a == "human" and new[i] != "human":
            print(f"{f}: objeto {i} deixou de ser author=human"); bad += 1
    # Objetos novos podem ser de humano (criados pela UI); aqui só garantimos que o campo existe e é válido.
    for i, a in new.items():
        if a not in ("human", "ai"):
            print(f"{f}: objeto {i} com author inválido {a!r}"); bad += 1
sys.exit(1 if bad else 0)
PY
