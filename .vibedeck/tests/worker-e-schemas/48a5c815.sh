#!/usr/bin/env bash
# Mudanças em schema/v1 (working tree vs HEAD) só podem ser compatíveis: nada removido/renomeado,
# nenhum required novo em objeto existente, sem troca de type/const/pattern, enum só cresce, sem fechar additionalProperties.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^schema/v1/'; then exit 77; fi
python3 -I - <<'PY'
import json, subprocess, sys, glob, os
bad = 0
def err(f, path, msg):
    global bad; print(f"{f}: {'/'.join(path) or '(raiz)'}: {msg}"); bad = 1
def types(s):
    t = s.get("type")
    return None if t is None else set([t] if isinstance(t, str) else t)
def cmp(f, old, new, path):
    if not isinstance(old, dict) or not isinstance(new, dict): return
    if "$ref" in old and old.get("$ref") != new.get("$ref"): err(f, path, f"$ref mudou: {old['$ref']} -> {new.get('$ref')}")
    ot, nt = types(old), types(new)
    if ot is not None and nt is not None and not ot <= nt: err(f, path, f"type restringido: {sorted(ot)} -> {sorted(nt)}")
    if ot is None and nt is not None: err(f, path, f"type novo em campo existente: {sorted(nt)}")
    if "enum" in new:
        if "enum" not in old: err(f, path, "enum novo restringe campo existente")
        elif not set(map(json.dumps, old["enum"])) <= set(map(json.dumps, new["enum"])):
            err(f, path, f"valores removidos do enum: {[x for x in old['enum'] if x not in new['enum']]}")
    for k in ("const", "pattern", "format"):
        if k in new and old.get(k) != new[k]: err(f, path, f"{k} mudou/adicionado: {old.get(k)!r} -> {new[k]!r}")
    for k in ("minLength", "minItems", "minimum", "minProperties"):
        if k in new and (k not in old or new[k] > old[k]): err(f, path, f"{k} mais restritivo: {old.get(k)} -> {new[k]}")
    for k in ("maxLength", "maxItems", "maximum", "maxProperties"):
        if k in new and (k not in old or new[k] < old[k]): err(f, path, f"{k} mais restritivo: {old.get(k)} -> {new[k]}")
    if old.get("additionalProperties", True) is not False and new.get("additionalProperties", True) is False:
        err(f, path, "additionalProperties passou a false")
    added_req = set(new.get("required", [])) - set(old.get("required", []))
    if added_req: err(f, path, f"campos passaram a obrigatórios: {sorted(added_req)}")
    for key in ("properties", "$defs", "definitions", "patternProperties"):
        op, np_ = old.get(key, {}), new.get(key, {})
        for name, sub in op.items():
            if name not in np_: err(f, path + [key, name], "removido/renomeado")
            else: cmp(f, sub, np_[name], path + [key, name])
    for key in ("items", "additionalProperties", "not", "if", "then", "else", "contains"):
        if isinstance(old.get(key), dict) and isinstance(new.get(key), dict): cmp(f, old[key], new[key], path + [key])
    for key in ("anyOf", "oneOf", "allOf"):
        o, n = old.get(key), new.get(key)
        if isinstance(o, list) and isinstance(n, list):
            if key == "allOf" and len(n) > len(o): err(f, path + [key], "allOf ganhou restrições")
            if key != "allOf" and len(n) < len(o): err(f, path + [key], f"{key} perdeu alternativas")
            for i, (a, b) in enumerate(zip(o, n)): cmp(f, a, b, path + [key, str(i)])
        elif n is not None and o is None and key == "allOf": err(f, path + [key], "allOf novo restringe campo existente")
tracked = subprocess.run(["git", "ls-tree", "--name-only", "HEAD", "schema/v1/"], capture_output=True, text=True).stdout.split()
for f in tracked:
    if not f.endswith(".json"): continue
    old = json.loads(subprocess.run(["git", "show", f"HEAD:{f}"], capture_output=True, text=True, check=True).stdout)
    if not os.path.exists(f):
        err(f, [], "schema removido da v1 (crie schema/v2)"); continue
    try: new = json.load(open(f))
    except Exception as e: err(f, [], f"JSON inválido ({e})"); continue
    cmp(f, old, new, [])
sys.exit(bad)
PY
