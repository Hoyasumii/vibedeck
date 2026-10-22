# Helpers compartilhados pelos scripts do tópico criar-projetos-remotos-via-ssh (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
CONN=Sources/VibeDeckCore/SSHConnection.swift
WS=Sources/VibeDeckCore/RemoteWorkspace.swift
EXEC=Sources/VibeDeckCore/RemoteExecution.swift
READ=Sources/VibeDeckCore/SSHReadTools.swift
SHEET=Sources/VibeDeckApp/SSHProjectView.swift
WELCOME=Sources/VibeDeckApp/WelcomeView.swift
APPF=Sources/VibeDeckApp/VibeDeckApp.swift
WINDOW=Sources/VibeDeckApp/ProjectWindow.swift
TERM=Sources/VibeDeckApp/ProjectTerminal.swift
TESTS=Tests/VibeDeckCoreTests/SSHProjectTests.swift
SCOPE='^Sources/VibeDeckCore/(SSHConnection|RemoteWorkspace|RemoteExecution|SSHReadTools)\.swift$|^Sources/VibeDeckApp/(SSHProjectView|WelcomeView|VibeDeckApp|ProjectWindow|ProjectTerminal)\.swift$|^Tests/VibeDeckCoreTests/SSHProjectTests\.swift$'
fail=0

# applies [regex extra]: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa com o escopo (+ extra).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  local re="$SCOPE"; [ -n "${1:-}" ] && re="$re|$1"
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$re" >/dev/null || exit 77
}

# need <arquivo> <regex ERE> <motivo>: falha se o padrão não aparece no arquivo.
need() { grep -qE -- "$2" "$1" || { echo "$1: $3"; fail=1; }; }

# needF <arquivo> <texto literal> <motivo>
needF() { grep -qF -- "$2" "$1" || { echo "$1: $3"; fail=1; }; }

# forbid <arquivo> <regex ERE> <motivo>: falha (com linha) se o padrão aparece.
forbid() {
  local hits
  if hits=$(grep -nE -- "$2" "$1"); then
    printf '%s\n' "$hits" | while IFS= read -r h; do echo "$1:${h%%:*}: $3"; done
    fail=1
  fi
}

# body <arquivo> <regex de início>: corpo da declaração (até a chave que fecha no mesmo recuo).
body() {
  RE="$2" awk 'BEGIN { re = ENVIRON["RE"] }
    !f && $0 ~ re { f=1; match($0, /^ */); ind=RLENGTH; print; if ($0 ~ /}[[:space:]]*$/ && $0 !~ /{[[:space:]]*$/) exit; next }
    f { print; match($0, /^ */); if (RLENGTH==ind && $0 ~ /^ *}/) exit }' "$1"
}

# in_body <arquivo> <regex início> <regex ERE> <motivo>: o padrão deve aparecer no corpo da declaração.
in_body() {
  local b; b=$(body "$1" "$2")
  [ -n "$b" ] || { echo "$1: declaração '$2' não encontrada"; fail=1; return; }
  grep -qE -- "$3" <<<"$b" || { echo "$1 ($2): $4"; fail=1; }
}

# not_in_body <arquivo> <regex início> <regex ERE> <motivo>
not_in_body() {
  local b; b=$(body "$1" "$2")
  [ -n "$b" ] || { echo "$1: declaração '$2' não encontrada"; fail=1; return; }
  if grep -qE -- "$3" <<<"$b"; then echo "$1 ($2): $4"; fail=1; fi
}

# run_tests <nome>...: confere que os @Test existem em SSHProjectTests e passaram.
# A suíte roda uma única vez por versão do código (cache em $TMPDIR com lock), pois vários scripts
# do tópico usam a mesma suíte e podem rodar em paralelo.
run_tests() {
  local name
  for name in "$@"; do
    grep -qE "func ${name}\(" "$TESTS" || { echo "$TESTS: teste '${name}' não existe mais"; exit 1; }
  done
  local key dir log lock waited=0
  key=$( { pwd; git ls-files -co --exclude-standard -- Sources Tests Package.swift Package.resolved 2>/dev/null | sort | xargs shasum 2>/dev/null; } | shasum | cut -c1-16)
  dir="${TMPDIR:-/tmp}/vibedeck-ssh-rules"; mkdir -p "$dir"
  log="$dir/$key.log"; lock="$dir/$key.lock"
  while [ ! -f "$log" ]; do
    # Lock órfão (script morto pelo limite de tempo) não pode travar as próximas execuções.
    find "$lock" -maxdepth 0 -mmin +3 -exec rmdir {} \; 2>/dev/null || true
    if mkdir "$lock" 2>/dev/null; then
      trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT
      local out
      if ! out=$(swift build --build-tests 2>&1); then rmdir "$lock"; printf '%s\n' "$out" | tail -20; exit 1; fi
      out=$(swift test --skip-build --filter 'SSHProjectTests' 2>&1) || true
      printf '%s\n' "$out" > "$log.tmp" && mv "$log.tmp" "$log"
      rmdir "$lock"
    else
      sleep 1; waited=$((waited + 1))
      [ $waited -lt 110 ] || { echo "tempo esgotado aguardando a suíte SSHProjectTests"; exit 1; }
    fi
  done
  grep -q "Test run with [1-9][0-9]* test" "$log" || { echo "SSHProjectTests não rodou:"; tail -15 "$log"; rm -f "$log"; exit 1; }
  for name in "$@"; do
    if ! grep -qF "✔ Test ${name}() passed" "$log"; then
      echo "$TESTS: teste ${name} falhou:"; grep -F "${name}()" "$log" | grep -v started | head -10; fail=1
    fi
  done
}

finish() { [ $fail -eq 0 ] || exit 1; exit 0; }
