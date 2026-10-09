#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Promover/despromover ideia só por ação explícita: botão do app, comando do CLI ou ferramenta MCP pedida pelo usuário.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
files = sorted(glob.glob("Sources/**/*.swift", recursive=True))
src = {f: open(f).read().split("\n") for f in files}
# 1. Só ProjectStore muda promotedTopic (promoteIdea / release).
for f, lines in src.items():
    for i, l in enumerate(lines):
        if re.search(r"\.promotedTopic\s*=[^=]", l) and f != "Sources/VibeDeckCore/ProjectStore.swift":
            fail(f"{f}:{i+1}: promotedTopic alterado fora do ProjectStore: {l.strip()}")
# 2. Chamadas a promoteIdea/unpromoteIdea só nos pontos explícitos.
allowed = {
    "Sources/VibeDeckCore/ProjectStore.swift",   # definição
    "Sources/VibeDeckApp/ProjectModel.swift",    # wrapper do app (chamado só por botão)
    "Sources/VibeDeckApp/IdeaView.swift",        # botão Promover / menu Despromover
    "Sources/vibedeck/CLI.swift",                # vibedeck ideas promote/unpromote
    "Sources/vibedeck/MCPServer.swift",          # promote_idea / unpromote_idea
}
for f, lines in src.items():
    for i, l in enumerate(lines):
        if re.search(r"\b(un)?promoteIdea\(", l) and not l.strip().startswith("//") and f not in allowed:
            fail(f"{f}:{i+1}: promove/despromove ideia fora de uma ação explícita do usuário: {l.strip()}")
# 3. No app, promoteIdea/unpromoteIdea do model só dentro de Button.
lines = src.get("Sources/VibeDeckApp/IdeaView.swift", [])
for i, l in enumerate(lines):
    if re.search(r"model\.(un)?promoteIdea\(", l):
        ctx = "\n".join(lines[max(0, i-4):i])
        if "Button" not in ctx:
            fail(f"Sources/VibeDeckApp/IdeaView.swift:{i+1}: promoção fora de um Button explícito")
pm = src.get("Sources/VibeDeckApp/ProjectModel.swift", [])
for i, l in enumerate(pm):
    if re.search(r"(?<!func )\b(un)?promoteIdea\(", l) and "store." not in l and "registerUndo" not in l and "func " not in l:
        fail(f"Sources/VibeDeckApp/ProjectModel.swift:{i+1}: ProjectModel promove ideia por conta própria: {l.strip()}")
# 4. MCP: descrição das ferramentas exige pedido do usuário.
mcp = "\n".join(src.get("Sources/vibedeck/MCPServer.swift", []))
for name in ("promote_idea", "unpromote_idea"):
    m = re.search(r'Tool\(name: "%s", description: "((?:[^"\\]|\\.)*)"' % name, mcp)
    if not m: fail(f"Sources/vibedeck/MCPServer.swift: ferramenta {name} não encontrada")
    elif "quando o usuário pedir" not in m.group(1):
        fail(f"Sources/vibedeck/MCPServer.swift: descrição de {name} não diz \"Só faça isso quando o usuário pedir\"")
sys.exit(bad)
PY
