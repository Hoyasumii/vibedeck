#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/vibedeck/"; then exit 77; fi
python3 -I - <<'PY'
import glob, re, sys
bad = []
tools = {f: open(f).read() for f in glob.glob("crates/vibedeck/src/mcp/tools/*.rs")}
allsrc = "\n".join(tools.values())
for f, t in tools.items():
    # docs.rs: write_doc sem generated cria doc humano de propósito (descrito na ferramenta)
    if "Author::Human" in t and not f.endswith("/docs.rs"): bad.append(f"{f}: ferramenta MCP não pode gravar Author::Human")
def desc(name):
    m = re.search(r'Tool::new\(\s*"%s",\s*"((?:[^"\\]|\\.)*)"' % name, allsrc)
    return m.group(1) if m else None
for name in ["add_review_item", "add_rule", "add_idea"]:
    d = desc(name)
    if d is None: bad.append(f"ferramenta {name} não encontrada")
    elif "author=ai" not in d: bad.append(f'descrição de {name} não diz "author=ai"')
# autoria: Author::Ai direto ou ctx.author(args), que só devolve human no modo `mcp --app` com author="human" explícito
tool_rs = open("crates/vibedeck/src/mcp/tool.rs").read()
m = re.search(r"pub fn author\(.*?\n    }\n", tool_rs, re.S)
if not m or not re.search(r"if !self\.app\s*\{\s*return Ok\(Author::Ai\)", m.group(0)): bad.append("mcp/tool.rs: ToolCtx::author deve devolver Author::Ai fora do modo --app")
for f in ["reviews.rs", "rules.rs", "ideas.rs"]:
    if not re.search(r"Author::Ai|ctx\.author\(", tools["crates/vibedeck/src/mcp/tools/" + f]): bad.append(f"mcp/tools/{f}: criação sem Author::Ai / ctx.author(args)")
# CLI: autoria sempre decidida pela flag --ai
for f in glob.glob("crates/vibedeck/src/cli/*.rs"):
    for i, l in enumerate(open(f).read().split("\n")):
        if re.search(r"Author::Human", l) and not re.search(r"if (a\.)?ai\s*\{\s*Author::Ai\s*\}\s*else\s*\{\s*Author::Human", l):
            bad.append(f"{f}:{i+1}: Author::Human fora do padrão `if ai {{ Author::Ai }} else {{ Author::Human }}`")
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
