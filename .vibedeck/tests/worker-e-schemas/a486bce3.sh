#!/usr/bin/env bash
# Toda resposta do worker leva os headers CORS; só GET/HEAD/OPTIONS (OPTIONS 204, outros 405, asset ausente 404).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^worker/src/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob
bad = 0
def err(f, n, msg):
    global bad; print(f"{f}:{n}: {msg}"); bad = 1
def call_args(src, start):
    depth = 0
    for i in range(start, len(src)):
        c = src[i]
        if c == "(": depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0: return src[start + 1:i]
    return src[start + 1:]
main = "worker/src/index.ts"
src = open(main).read()
line = lambda s, i: s.count("\n", 0, i) + 1
m = re.search(r'const CORS\s*=\s*\{(.*?)\}', src, re.S)
if not m:
    err(main, 1, "constante CORS não encontrada")
else:
    body = m.group(1)
    if not re.search(r'"Access-Control-Allow-Origin":\s*"\*"', body):
        err(main, line(src, m.start()), "CORS sem Access-Control-Allow-Origin: *")
    mm = re.search(r'"Access-Control-Allow-Methods":\s*"([^"]*)"', body)
    if not mm or {x.strip() for x in mm.group(1).split(",")} != {"GET", "HEAD", "OPTIONS"}:
        err(main, line(src, m.start()), "Access-Control-Allow-Methods deve ser exatamente GET, HEAD, OPTIONS")
if not re.search(r'request\.method\s*===\s*"OPTIONS"\)\s*return new Response\(null,\s*\{\s*status:\s*204,\s*headers:\s*CORS', src):
    err(main, 1, "OPTIONS deve responder 204 com headers: CORS")
if not re.search(r'request\.method\s*!==\s*"GET"\s*&&\s*request\.method\s*!==\s*"HEAD"', src) or \
   not re.search(r'status:\s*405,\s*headers:\s*CORS', src):
    err(main, 1, "métodos além de GET/HEAD devem responder 405 com headers: CORS")
if not re.search(r'status:\s*404,\s*headers:\s*CORS', src):
    err(main, 1, "asset inexistente deve responder 404 com headers: CORS")
# Variáveis Headers que recebem CORS (ex.: headers.set(k, v) em loop sobre CORS).
cors_vars = set(re.findall(r'for\s*\(const \[(?:\w+),\s*(?:\w+)\] of Object\.entries\(CORS\)\)\s*(\w+)\.set\(', src))
for f in sorted(glob.glob("worker/src/**/*.ts", recursive=True)):
    s = open(f).read()
    for m in re.finditer(r'\b(new Response|Response\.json|Response\.redirect)\s*\(', s):
        args = call_args(s, m.end() - 1)
        ok = "CORS" in args or any(re.search(r'\bheaders(:\s*|\s*[,}])' if v == "headers" else rf'headers:\s*{v}\b', args) for v in cors_vars)
        if m.group(1) == "Response.redirect": ok = False
        if not ok:
            err(f, line(s, m.start()), f"{m.group(1)}(...) sem headers CORS")
sys.exit(bad)
PY
