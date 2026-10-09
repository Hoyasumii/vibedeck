#!/usr/bin/env bash
# Scripts .sh: set -euo pipefail; os que compilam Swift fazem cd "$(dirname "$0")/.." e source scripts/env.sh (test.sh é exceção).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ]; then
  files=$(printf '%s\n' "$VIBEDECK_FILES" | grep -E '^scripts/.*\.sh$' || true)
  [ -n "$files" ] || exit 77
else
  files=$(ls scripts/*.sh)
fi

fail=0
for f in $files; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = "env.sh" ] && continue
  head -1 "$f" | grep -Eq '^#!/usr/bin/env bash$' || { echo "$f:1: shebang deve ser #!/usr/bin/env bash"; fail=1; }
  n=$(grep -n '^set -euo pipefail$' "$f" | head -1 | cut -d: -f1 || true)
  [ -n "$n" ] || { echo "$f: falta 'set -euo pipefail'"; fail=1; }
  [ "$(basename "$f")" = "test.sh" ] && continue
  if grep -Eq '^\s*(swift (build|test|run)|xcodebuild)\b' "$f"; then
    grep -q '^cd "\$(dirname "\$0")/\.\."$' "$f" || { echo "$f: compila Swift mas falta cd \"\$(dirname \"\$0\")/..\""; fail=1; }
    grep -q '^source scripts/env\.sh$' "$f" || { echo "$f: compila Swift mas falta 'source scripts/env.sh'"; fail=1; }
  fi
done
exit $fail
