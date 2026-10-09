#!/usr/bin/env bash
# Toda entidade com autoria tem author (schema incluso), o app grava human, MCP grava ai, CLI só com --ai,
# o app mostra o badge "Criado por IA" e a IA (MCP) não apaga itens, regras nem ideias.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/|^schema/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
core = {f: open(f).read() for f in glob.glob("Sources/VibeDeckCore/*.swift")}
app = {f: open(f).read() for f in glob.glob("Sources/VibeDeckApp/*.swift")}
models = re.search(r"enum Author: String[^{]*\{\s*case (\w+), (\w+)", core["Sources/VibeDeckCore/Models.swift"])
if not models or {models.group(1), models.group(2)} != {"human", "ai"}:
    fail("Sources/VibeDeckCore/Models.swift: Author deve ser human | ai")
# Entidades com autoria → badge no app (<var>.author == .ai seguido de sparkles/"IA").
authored = []
for f, s in core.items():
    for m in re.finditer(r"public struct (\w+)\b[^{]*\{", s):
        i, depth = m.end(), 1
        while depth and i < len(s):
            depth += {"{": 1, "}": -1}.get(s[i], 0); i += 1
        if re.search(r"public var author: Author", s[m.start():i]):
            authored.append((m.group(1), f, s[:m.start()].count("\n") + 1))
allapp = "\n".join(app.values())
for name, f, line in authored:
    words = re.findall(r"[A-Z][a-z]*", name)
    names = {name[0].lower() + name[1:], words[-1].lower()}
    if name == "ProjectPattern": names.add("pattern")
    ok = False
    for n in names:
        for m in re.finditer(r"\b%s\.author == \.ai" % re.escape(n), allapp):
            tail = allapp[m.end():m.end() + 250]
            if re.search(r'sparkles|"IA"|Criad[oa] por IA|pela IA', tail): ok = True
    if not ok: fail(f"{f}:{line}: {name} tem author mas o app não mostra o badge de IA ({' / '.join(sorted(names))}.author == .ai)")
# O app nunca grava author: .ai; o CLI só com a flag --ai.
for f, s in app.items():
    for i, l in enumerate(s.split("\n")):
        if re.search(r"author: \.ai\b", l): fail(f"{f}:{i+1}: o app grava author .ai (deveria ser human)")
cli = open("Sources/vibedeck/CLI.swift").read().split("\n")
for i, l in enumerate(cli):
    if re.search(r"author: \.ai\b", l) and "ai ?" not in l: fail(f"Sources/vibedeck/CLI.swift:{i+1}: CLI grava author .ai sem --ai")
# MCP: criação com author .ai (as do humano não são apagadas: sem ferramentas de remoção dessas entidades).
mcp = open("Sources/vibedeck/MCPServer.swift").read()
for name in ("add_review_item", "add_rule", "add_idea", "add_idea_rule"):
    m = re.search(r'case "%s":(.*?)(?=\n        case "|\n        default:)' % name, mcp, re.S)
    if not m: fail(f"Sources/vibedeck/MCPServer.swift: ferramenta {name} não encontrada")
    elif "author: .ai" not in m.group(1): fail(f"Sources/vibedeck/MCPServer.swift: {name} não grava author: .ai")
for m in re.finditer(r'Tool\(name: "((?:delete|remove)_(?:review|item|rule|idea|topic|group|doc)\w*)"', mcp):
    fail(f"Sources/vibedeck/MCPServer.swift: ferramenta {m.group(1)} deixa a IA apagar o que pode ser de humano")
# Schemas das entidades com autoria descrevem author human|ai.
for sf in sorted(glob.glob("schema/v1/*.schema.json")):
    s = open(sf).read()
    if '"author"' in s and not re.search(r'"author"[^}]*"enum":\s*\[\s*"human",\s*"ai"\s*\]|"enum":\s*\[\s*"human",\s*"ai"\s*\]', s):
        fail(f"{sf}: author sem enum human|ai")
for sf, needed in (("schema/v1/review-group.schema.json", 1), ("schema/v1/rule-topic.schema.json", 1), ("schema/v1/idea.schema.json", 1)):
    if '"author"' not in open(sf).read(): fail(f"{sf}: falta author")
sys.exit(bad)
PY
