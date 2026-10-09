#!/usr/bin/env bash
# swift.yml ignora worker/**; worker.yml só dispara com worker/**, schema/** e o próprio workflow; deploy só na main após o check.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -q '^\.github/workflows/'; then exit 77; fi

fail=0
bad() { echo "$1"; fail=1; }
S=.github/workflows/swift.yml
W=.github/workflows/worker.yml

grep -Eq 'paths-ignore: *\[.*"worker/\*\*"' "$S" || bad "$S: paths-ignore deve incluir worker/**"
[ "$(grep -c 'paths-ignore:' "$S")" -ge 2 ] || bad "$S: paths-ignore deve existir em push e pull_request"
grep -q 'runs-on: macos-latest' "$S" || bad "$S: job de teste deve rodar no macos-latest"
grep -Eq 'xcode-version: *latest-stable' "$S" || bad "$S: falta xcode-version: latest-stable"
grep -Eq 'run: swift test' "$S" || bad "$S: falta 'swift test'"

[ "$(grep -c '^    paths: \["worker/\*\*", "schema/\*\*", "\.github/workflows/worker\.yml"\]' "$W")" -eq 2 ] \
  || bad "$W: push e pull_request devem ter paths: [\"worker/**\", \"schema/**\", \".github/workflows/worker.yml\"]"
grep -q '^  deploy:' "$W" || bad "$W: job deploy não encontrado"
dep=$(awk '/^  deploy:/{f=1;next} f' "$W")
echo "$dep" | grep -q 'needs: check' || bad "$W: deploy deve ter needs: check"
echo "$dep" | grep -Eq "if: github\.ref == 'refs/heads/main' && github\.event_name != 'pull_request'" || bad "$W: deploy deve rodar só em push na main (if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request')"
echo "$dep" | grep -q 'concurrency: worker-deploy' || bad "$W: deploy deve ter concurrency: worker-deploy"
echo "$dep" | grep -q 'secrets\.CLOUDFLARE_API_TOKEN' || bad "$W: deploy sem secrets.CLOUDFLARE_API_TOKEN"
echo "$dep" | grep -q 'secrets\.CLOUDFLARE_ACCOUNT_ID' || bad "$W: deploy sem secrets.CLOUDFLARE_ACCOUNT_ID"
grep -q 'wrangler-action' "$W" || bad "$W: deploy deve usar wrangler"
exit $fail
