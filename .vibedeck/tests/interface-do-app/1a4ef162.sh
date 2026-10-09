#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Tópico apagado por qualquer caminho despromove a ideia.
pm=Sources/VibeDeckApp/ProjectModel.swift
python3 -I - "$pm" <<'PY' || fail=1
import re, sys
src = open(sys.argv[1]).read().splitlines()
def body(sig):
    for i, l in enumerate(src):
        if re.search(sig, l):
            depth, out = 0, []
            for j in range(i, len(src)):
                out.append(src[j]); depth += src[j].count("{") - src[j].count("}")
                if depth == 0 and "{" in "".join(out): return "\n".join(out), i + 1
    return None, 0
bad = 0
for sig, what in [(r'func deleteTopic\(', "Mover para o Lixo (deleteTopic)"),
                  (r'func handleExternalChanges\(', "handleExternalChanges"),
                  (r'func (load|open|start)\w*\(', "abertura do projeto")]:
    b, n = body(sig)
    if what.startswith("abertura"):
        # a abertura é o init/reload inicial: procura a chamada em qualquer lugar fora desses dois
        if not re.search(r'releaseOrphanedIdeas\(\)', "\n".join(src)) or "// Topics deleted while the app was closed" not in "\n".join(src):
            print(f"{sys.argv[1]}: abertura do projeto não despromove ideias órfãs"); bad = 1
        continue
    if b is None or "releaseOrphanedIdeas" not in b:
        print(f"{sys.argv[1]}:{n}: {what} não chama releaseOrphanedIdeas"); bad = 1
sys.exit(bad)
PY
iv=Sources/VibeDeckApp/IdeaView.swift
grep -q 'Button("Despromover", role: .destructive)' "$iv" || bad "$iv" "menu de contexto 'Despromover' ausente"
grep -q 'Promover para Regras' "$iv" || bad "$iv" "botão 'Promover para Regras' ausente"
grep -q 'Tópico: ' "$iv" || bad "$iv" "badge 'Tópico: …' ausente"
grep -n 'releaseOrphanedIdeas' Sources/VibeDeckCore/ProjectStore.swift >/dev/null || bad Sources/VibeDeckCore/ProjectStore.swift "ProjectStore.releaseOrphanedIdeas ausente"
exit $fail
