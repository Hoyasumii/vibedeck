#!/usr/bin/env bash
# Toda entidade com autoria tem author (schema incluso); o MCP (catálogo de IA) grava ai e não apaga nada, o CLI só grava ai com --ai,
# o app grava human (ai só nas propostas de IA) e mostra o badge "Criado por IA".
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^(Sources|crates)/|^schema/" >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
M = "crates/vibedeck-core/src/"
common = open(M + "model/common.rs").read()
m = re.search(r"pub enum Author \{\s*#\[default\]\s*(\w+),\s*(\w+),?\s*\}", common)
if not m or {m.group(1), m.group(2)} != {"Human", "Ai"}:
    fail(M + "model/common.rs: Author deve ser Human | Ai")
# Entidades com autoria (Rust) → badge no app (<var>.author == .ai seguido de sparkles/"IA").
authored = []
for f in sorted(glob.glob(M + "model/*.rs")):
    s = strip_tests(open(f).read())
    for sm in re.finditer(r"pub struct (\w+)\s*\{", s):
        i, depth = sm.end(), 1
        while depth and i < len(s):
            depth += {"{": 1, "}": -1}.get(s[i], 0); i += 1
        if re.search(r"pub author: Author", s[sm.start():i]) and not sm.group(1).endswith("Wire"):
            authored.append((sm.group(1), f, s[:sm.start()].count("\n") + 1))
    if f.endswith("persona.rs"):   # Agent/Command/Skill saem de uma macro
        for n in re.findall(r"^\s+(\w+), \w+Wire, ", s, re.M): authored.append((n, f, 1))
app = {f: open(f).read() for f in glob.glob("Sources/VibeDeckApp/**/*.swift", recursive=True)}
allapp = "\n".join(app.values())
for name, f, line in authored:
    words = re.findall(r"[A-Z][a-z]*", name)
    names = {name[0].lower() + name[1:], words[-1].lower()}
    if name == "ProjectPattern": names.add("pattern")
    if name == "RuleCheck": names.add("check")
    ok = False
    for n in names:
        for mm in re.finditer(r"\b%s\.author == \.ai" % re.escape(n), allapp):
            tail = allapp[mm.end():mm.end() + 250]
            if re.search(r'sparkles|"IA"|Criad[oa] por IA|pela IA', tail): ok = True
    if not ok: fail(f"{f}:{line}: {name} tem author mas o app não mostra o badge de IA ({' / '.join(sorted(names))}.author == .ai)")
# O app grava human; author .ai só ao criar a partir de uma proposta de IA ("nasce com autor `ai`" / "AI-authored").
for f, s in app.items():
    lines = s.split("\n")
    for i, l in enumerate(lines):
        if re.search(r"author: \.ai\b", l) and not re.search(r"nasce com autor `ai`|AI-authored", "\n".join(lines[max(0, i - 25):i])):
            fail(f"{f}:{i+1}: o app grava author .ai fora de uma proposta de IA (deveria ser human)")
# CLI: Author::Ai só com a flag --ai.
for f in sorted(glob.glob("crates/vibedeck/src/cli/*.rs")):
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if re.search(r"Author::Ai\b", l) and not re.search(r"==\s*Author::Ai|if (a\.)?ai\b|if ai\s*\{", l) and not l.strip().startswith("//"):
            fail(f"{f}:{i+1}: CLI grava Author::Ai sem --ai: {l.strip()}")
# MCP: criação com author da chamada (ai fora do modo app) — ToolCtx::author.
tool = open("crates/vibedeck/src/mcp/tool.rs").read()
mm = re.search(r"pub fn author\(.*?\n    \}", tool, re.S)
if not mm or not re.search(r"if !self\.app \{\s*return Ok\(Author::Ai\);", mm.group(0)):
    fail("crates/vibedeck/src/mcp/tool.rs: ToolCtx::author deve devolver Author::Ai fora do modo app")
for name, f in (("add_review_item", "reviews"), ("add_rule", "rules"), ("add_idea", "ideas"), ("add_idea_rule", "ideas")):
    s = open(f"crates/vibedeck/src/mcp/tools/{f}.rs").read()
    if f'"{name}"' not in s: fail(f"crates/vibedeck/src/mcp/tools/{f}.rs: ferramenta {name} não encontrada")
    elif "ctx.author(" not in s: fail(f"crates/vibedeck/src/mcp/tools/{f}.rs: {name} não grava a autoria (ctx.author)")
# O catálogo de IA (todas as tools fora de tools/app.rs, que é só do modo --app) não apaga review/item/rule/idea/topic/group/doc.
for f in sorted(glob.glob("crates/vibedeck/src/mcp/tools/*.rs")):
    if f.endswith("/app.rs") or f.endswith("/mod.rs"): continue
    for m in re.finditer(r'Tool::new\(\s*"((?:delete|remove)_(?:review|item|rule|idea|topic|group|doc)\w*)"', open(f).read()):
        fail(f"{f}: ferramenta {m.group(1)} deixa a IA apagar o que pode ser de humano (só o modo --app, tools/app.rs, apaga)")
# Schemas das entidades com autoria descrevem author human|ai.
for sf in sorted(glob.glob("schema/v1/*.schema.json")):
    s = open(sf).read()
    if '"author"' in s and not re.search(r'"enum":\s*\[\s*"human",\s*"ai"\s*\]', s):
        fail(f"{sf}: author sem enum human|ai")
for sf in ("schema/v1/review-group.schema.json", "schema/v1/rule-topic.schema.json", "schema/v1/idea.schema.json"):
    if '"author"' not in open(sf).read(): fail(f"{sf}: falta author")
sys.exit(bad)
PY
