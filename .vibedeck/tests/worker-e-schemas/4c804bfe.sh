#!/usr/bin/env bash
# Mesmo job check de .github/workflows/worker.yml: npm ci && npm run sync && npm run typecheck (em worker/).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^(worker|schema)/|^\.github/workflows/worker\.yml$'; then exit 77; fi
if ! command -v npm >/dev/null 2>&1; then
  for d in "$HOME"/.local/share/mise/installs/node/*/bin /opt/homebrew/bin /usr/local/bin; do
    [ -x "$d/npm" ] && { PATH="$d:$PATH"; break; }
  done
fi
command -v npm >/dev/null 2>&1 || { echo "npm não encontrado no PATH"; exit 2; }
cd worker
# Sem rede: só reinstala (do cache, --offline) se node_modules não bate com o package-lock.json.
in_sync() {
  python3 -I - <<'PY2'
import json, sys
lock = json.load(open("package-lock.json"))["packages"]
try: inst = json.load(open("node_modules/.package-lock.json"))["packages"]
except Exception: sys.exit(1)
for k, v in lock.items():
    if not k: continue
    if k in inst:
        if inst[k].get("version") != v.get("version"): sys.exit(1)
    elif not v.get("optional"): sys.exit(1)  # opcionais de outra plataforma não são instalados
sys.exit(0 if set(inst) <= set(lock) else 1)
PY2
}
if ! in_sync; then
  npm ci --offline --no-audit --no-fund || { echo "worker/: npm ci --offline falhou (dependências fora do cache?)"; exit 1; }
fi
npm run --silent sync
npm run --silent typecheck || { echo "worker/: npm run typecheck falhou"; exit 1; }
echo "worker/: sync + typecheck ok ($(node -v))"
