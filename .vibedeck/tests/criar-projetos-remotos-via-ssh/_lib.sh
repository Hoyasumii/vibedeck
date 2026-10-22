# Helpers compartilhados pelos scripts do tópico criar-projetos-remotos-via-ssh (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
# Projeto SSH: o Core Rust roda no servidor (`ssh host vibedeck mcp -C <dir>`) e o app só fala MCP com ele; não há
# espelho local, sincronização nem edição offline. O app mantém a conexão OpenSSH (SSHConnection), o seletor de pasta
# remota e o terminal.
CONN=Sources/VibeDeckApp/Core/Support/SSHConnection.swift
WS=Sources/VibeDeckApp/Core/RemoteWorkspace.swift
EXEC=Sources/VibeDeckApp/Core/Support/RemoteExecution.swift
READ=Sources/VibeDeckApp/Core/Support/SSHReadTools.swift
CSTORE=Sources/VibeDeckApp/Core/CoreStore.swift
SHEET=Sources/VibeDeckApp/SSHProjectView.swift
STATUS=Sources/VibeDeckApp/V2/V2RemoteEnvironment.swift
WELCOME=Sources/VibeDeckApp/WelcomeView.swift
APPF=Sources/VibeDeckApp/VibeDeckApp.swift
TERM=Sources/VibeDeckApp/ProjectTerminal.swift
SCOPE='^Sources/VibeDeckApp/Core/(Support/(SSHConnection|RemoteExecution|SSHReadTools)|RemoteWorkspace|CoreStore|CoreClient)\.swift$|^Sources/VibeDeckApp/Core/AI/[^/]*\.swift$|^Sources/VibeDeckApp/(SSHProjectView|WelcomeView|VibeDeckApp|ProjectTerminal|ReviewDiscover|AIReadOnlyOperation)\.swift$|^Sources/VibeDeckApp/V2/V2(RemoteEnvironment|ProjectWindow|StatusBar)\.swift$|^crates/vibedeck-core/src/rules/(runner|execution)\.rs$'
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

finish() { [ $fail -eq 0 ] || exit 1; exit 0; }
