#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Promover/despromover ideia só por ação explícita: botão do app, comando do CLI ou ferramenta MCP pedida pelo usuário.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^(Sources|crates)/" >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
# ---- Core Rust ----
# 1. Só ideas.rs muda promoted_topic (promote_idea / release).
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f: continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if re.search(r"\.promoted_topic\s*=[^=]", l) and f != "crates/vibedeck-core/src/ideas.rs":
            fail(f"{f}:{i+1}: promoted_topic alterado fora de ideas.rs: {l.strip()}")
# 2. Chamadas a promote_idea/unpromote_idea só nos pontos explícitos.
allowed_rs = {
    "crates/vibedeck-core/src/ideas.rs",            # definição
    "crates/vibedeck-core/src/app.rs",              # `mcp --app`: ideia como pedido de implementação (botão do app)
    "crates/vibedeck/src/cli/ideas.rs",             # vibedeck ideas promote/unpromote
    "crates/vibedeck/src/mcp/tools/ideas.rs",       # promote_idea / unpromote_idea
}
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f: continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if re.search(r"\b(un)?promote_idea\(", l) and not l.strip().startswith("//") and f not in allowed_rs:
            fail(f"{f}:{i+1}: promove/despromove ideia fora de uma ação explícita do usuário: {l.strip()}")
# 3. MCP: a descrição das ferramentas exige pedido do usuário.
mcp = open("crates/vibedeck/src/mcp/tools/ideas.rs").read()
for name in ("promote_idea", "unpromote_idea"):
    m = re.search(r'Tool::new\(\s*"%s",\s*"((?:[^"\\]|\\.)*)"' % name, mcp)
    if not m: fail(f"crates/vibedeck/src/mcp/tools/ideas.rs: ferramenta {name} não encontrada")
    elif "quando o usuário pedir" not in m.group(1):
        fail(f"crates/vibedeck/src/mcp/tools/ideas.rs: descrição de {name} não diz \"Só faça isso quando o usuário pedir\"")
# ---- App Swift: fala com o Core por MCP (store.call("promote_idea")) ----
files = sorted(glob.glob("Sources/**/*.swift", recursive=True))
src = {f: open(f).read().split("\n") for f in files}
for f, lines in src.items():
    for i, l in enumerate(lines):
        if re.search(r"\.promotedTopic\s*=[^=]", l) and f != "Sources/VibeDeckApp/ProjectModel.swift":
            fail(f"{f}:{i+1}: promotedTopic alterado fora do ProjectModel: {l.strip()}")
allowed_sw = {"Sources/VibeDeckApp/ProjectModel.swift",   # wrapper do app (chamado por botão / fluxo "Implementar")
              "Sources/VibeDeckApp/IdeaView.swift"}       # botão Promover / menu Despromover
for f, lines in src.items():
    for i, l in enumerate(lines):
        if re.search(r"\b(un)?promote_?[iI]dea\b", l) and not l.strip().startswith(("//", "///")) and f not in allowed_sw \
           and not f.endswith("AgentsGuide.swift"):
            fail(f"{f}:{i+1}: promove/despromove ideia fora de uma ação explícita do usuário: {l.strip()}")
# No app, promoteIdea/unpromoteIdea do model só dentro de um botão (ou do callback de implementação) em IdeaView.
lines = src.get("Sources/VibeDeckApp/IdeaView.swift", [])
def implementation_button_callback(index):
    for start, line in enumerate(lines):
        if "onImplement: implementation ? {" not in line: continue
        if "RuleDiscoverButton(" not in "\n".join(lines[max(0, start-5):start]): continue
        depth = 0
        for end in range(start, len(lines)):
            depth += lines[end].count("{") - lines[end].count("}")
            if depth == 0:
                if start <= index <= end: return True
                break
    return False
for i, l in enumerate(lines):
    if re.search(r"model\.(un)?promoteIdea\(", l):
        ctx = "\n".join(lines[max(0, i-6):i])
        if "Button" not in ctx and not implementation_button_callback(i) and "takePendingPromotion" not in ctx:
            fail(f"Sources/VibeDeckApp/IdeaView.swift:{i+1}: promoção fora de um Button explícito")
# ProjectModel: chamadas a promoteIdea só no próprio wrapper ou no fluxo explícito "Implementar ideia" (prepareIdeaImplementation).
pm = src.get("Sources/VibeDeckApp/ProjectModel.swift", [])
fn = None
for i, l in enumerate(pm):
    m = re.search(r"\bfunc (\w+)", l)
    if m: fn = m.group(1)
    if re.search(r"(?<!func )\b(un)?promoteIdea\(", l) and "store.call" not in l and not l.strip().startswith("//"):
        if fn not in ("prepareIdeaImplementation", "promoteIdea", "unpromoteIdea"):
            fail(f"Sources/VibeDeckApp/ProjectModel.swift:{i+1}: ProjectModel promove ideia por conta própria (fora do fluxo 'Implementar'): {l.strip()}")
sys.exit(bad)
PY
