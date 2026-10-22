#!/usr/bin/env bash
# rust.yml só dispara com crates/**, Cargo.*, schema/**, scripts/** e o próprio workflow e roda `cargo test`; worker.yml só dispara com
# worker/**, schema/** e o próprio workflow; deploy só na main após o check. Sem .github/workflows (CI desativado em 63a1a38): 77.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -q '^\.github/workflows/'; then exit 77; fi
# CI/CD desativado temporariamente: não há workflows para verificar.
[ -d .github/workflows ] && ls .github/workflows/*.yml >/dev/null 2>&1 || exit 77

fail=0
bad() { echo "$1"; fail=1; }
R=.github/workflows/rust.yml
W=.github/workflows/worker.yml

if [ -f "$R" ]; then
  [ "$(grep -c '^    paths: \[.*"crates/\*\*".*"Cargo\.\*".*"schema/\*\*".*"\.github/workflows/rust\.yml"\]' "$R")" -eq 2 ] \
    || bad "$R: push e pull_request devem ter paths com crates/**, Cargo.*, schema/** e .github/workflows/rust.yml"
  grep -Eq 'run: cargo test' "$R" || bad "$R: falta 'cargo test'"
  grep -Eq 'run: cargo clippy .*-D warnings' "$R" || bad "$R: falta 'cargo clippy ... -D warnings'"
  grep -Eq 'run: cargo fmt --all --check' "$R" || bad "$R: falta 'cargo fmt --all --check'"
fi

if [ -f "$W" ]; then
  # paths do worker: worker/**, schema/** e o próprio workflow são obrigatórios; vibedeck.json e .vibedeck/** são
  # aceitos (o workflow também valida as regras do projeto). Qualquer outro caminho (crates/**, Sources/**) reprova.
  wp=$(grep -E '^    paths: \[' "$W" || true)
  [ "$(grep -c . <<<"$wp")" -eq 2 ] || bad "$W: push e pull_request devem ter cada um uma linha paths: [...]"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    for need in '"worker/**"' '"schema/**"' '".github/workflows/worker.yml"'; do
      grep -qF "$need" <<<"$line" || bad "$W: paths sem $need"
    done
    extra=$(grep -o '"[^"]*"' <<<"$line" | grep -vxF -e '"worker/**"' -e '"schema/**"' -e '".github/workflows/worker.yml"' -e '"vibedeck.json"' -e '".vibedeck/**"' || true)
    [ -z "$extra" ] || bad "$W: paths com caminhos alheios ao worker: $(tr '\n' ' ' <<<"$extra")"
  done <<<"$wp"
  grep -q '^  deploy:' "$W" || bad "$W: job deploy não encontrado"
  dep=$(awk '/^  deploy:/{f=1;next} f' "$W")
  grep -q 'needs: check' <<<"$dep" || bad "$W: deploy deve ter needs: check"
  grep -Eq "if: github\.ref == 'refs/heads/main' && github\.event_name != 'pull_request'" <<<"$dep" || bad "$W: deploy deve rodar só em push na main (if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request')"
  grep -q 'concurrency: worker-deploy' <<<"$dep" || bad "$W: deploy deve ter concurrency: worker-deploy"
  grep -q 'secrets\.CLOUDFLARE_API_TOKEN' <<<"$dep" || bad "$W: deploy sem secrets.CLOUDFLARE_API_TOKEN"
  grep -q 'secrets\.CLOUDFLARE_ACCOUNT_ID' <<<"$dep" || bad "$W: deploy sem secrets.CLOUDFLARE_ACCOUNT_ID"
  grep -q 'wrangler-action' "$W" || bad "$W: deploy deve usar wrangler"
fi
exit $fail
