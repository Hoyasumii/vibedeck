#!/usr/bin/env bash
# worker/public é gerado por `npm run sync` a partir de schema/v1: não pode ser editado nem versionado.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^(worker|schema)/'; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
while IFS= read -r f; do
  [ -n "$f" ] && bad "$f" "arquivo gerado (worker/public) alterado na tarefa; edite schema/v1/*.schema.json"
done < <(printf '%s\n' "${VIBEDECK_FILES:-}" | grep -E '^worker/public(/|$)' || true)
while IFS= read -r f; do
  [ -n "$f" ] && bad "$f" "worker/public não deve ser versionado (é apagado e recriado pelo npm run sync)"
done < <(git ls-files -- worker/public)
git check-ignore -q worker/public/v1/x.schema.json || bad ".gitignore" "worker/public/ deixou de ser ignorado"
sync=$(python3 -I -c 'import json;print(json.load(open("worker/package.json"))["scripts"].get("sync",""))')
[ "$sync" = "rm -rf public && mkdir -p public && cp -R ../schema/v1 public/v1" ] \
  || bad "worker/package.json" "script sync não regenera public a partir de ../schema/v1: '$sync'"
exit $fail
