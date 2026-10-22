# Ajudantes comuns do tópico "modo de implementação de ideia aprovada". Rápido, sem rede.
cd "${VIBEDECK_ROOT:-.}"
bad=0
RULES=Sources/VibeDeckApp/Core/Model/Rules.swift
IDEAS_RS=crates/vibedeck-core/src/ideas.rs
WFOPS=crates/vibedeck-core/src/workflows/ops.rs
WFENGINE=crates/vibedeck-core/src/workflows/engine.rs
MODEL=Sources/VibeDeckApp/ProjectModel.swift
SESSION=Sources/VibeDeckApp/ClaudeSession.swift
WFV=Sources/VibeDeckApp/WorkflowView.swift
IDEAV=Sources/VibeDeckApp/IdeaView.swift
WINDOW=Sources/VibeDeckApp/V2/V2ProjectWindow.swift
CORESTORE=Sources/VibeDeckApp/Core/CoreStore+Items.swift
CLI_DIR=crates/vibedeck/src/cli
MCP_DIR=crates/vibedeck/src/mcp
IDEAS_T=crates/vibedeck-core/tests/ideas_core.rs

# applies REGEX: sai com 77 quando $VIBEDECK_FILES não está vazio e nenhum arquivo casa a regex (ERE).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -Eq -e "$1" || exit 77
}
SCOPE='^(Sources/VibeDeckApp/|Tests/VibeDeckAppTests/|crates/vibedeck-core/(src|tests)/(ideas|workflows)|crates/vibedeck/src/(cli|mcp)/)'

# lbl FILE: nome exibido (o recorte temporário da folha aparece como WorkflowView.swift).
lbl() { if [ "$1" = "${SHEET:-}" ]; then echo "$WFV (IdeaImplementationSheet)"; else echo "$1"; fi; }
has()  { grep -Eq -e "$2" "$1" 2>/dev/null || { echo "$(lbl "$1"): $3"; bad=1; }; }
hasF() { grep -Fq -e "$2" "$1" 2>/dev/null || { echo "$(lbl "$1"): $3"; bad=1; }; }
none() { local m; if m=$(grep -nE -e "$2" "$1" 2>/dev/null); then echo "$(lbl "$1"): $3"; echo "$m"; bad=1; fi; }

# block FILE START: imprime o bloco de chaves que começa na primeira linha que contém START (texto literal).
block() {
  python3 -I - "$1" "$2" <<'PY'
import sys
f, start = sys.argv[1], sys.argv[2]
s = open(f).read()
i = s.find(start)
if i < 0: sys.exit(0)
j = s.index("{", i); depth = 0
for k in range(j, len(s)):
    if s[k] == "{": depth += 1
    elif s[k] == "}":
        depth -= 1
        if depth == 0: print(s[i:k+1]); break
PY
}
# inblock FILE START REGEX MSG / notinblock: regex dentro (ou fora) do bloco.
inblock()    { local b; b=$(block "$1" "$2"); [ -n "$b" ] || { echo "$(lbl "$1"): bloco '$2' não encontrado"; bad=1; return; }
               grep -Eq -e "$3" <<<"$b" || { echo "$(lbl "$1") ($2): $4"; bad=1; }; }
notinblock() { local b m; b=$(block "$1" "$2"); [ -n "$b" ] || { echo "$(lbl "$1"): bloco '$2' não encontrado"; bad=1; return; }
               if m=$(grep -nE -e "$3" <<<"$b"); then echo "$(lbl "$1") ($2): $4"; echo "$m"; bad=1; fi; }

# rtest FILE NAME...: confere que o teste Rust existe (rodam em `cargo test`; aqui só a presença, para ser rápido).
rtest() { local f=$1; shift; local n; for n in "$@"; do grep -qE "fn ${n}\(" "$f" || { echo "$f: teste '${n}' não existe"; bad=1; }; done; }
finish() { exit $bad; }
# SHEET: arquivo temporário com só o corpo de IdeaImplementationSheet (para buscar .task, confirm etc. sem colidir).
SHEET=$(mktemp); trap 'rm -f "$SHEET"' EXIT
block "$WFV" "struct IdeaImplementationSheet" >"$SHEET"
[ -s "$SHEET" ] || { echo "$WFV: struct IdeaImplementationSheet não encontrada"; bad=1; }
# segment FILE A B: texto entre a primeira ocorrência literal de A e a próxima de B.
segment() { python3 -I -c 'import sys;s=open(sys.argv[1]).read();i=s.find(sys.argv[2]);j=s.find(sys.argv[3],i+1) if i>=0 else -1;print(s[i:j] if j>i else "")' "$1" "$2" "$3"; }
