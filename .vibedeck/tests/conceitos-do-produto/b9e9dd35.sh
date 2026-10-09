#!/usr/bin/env bash
# Todo conceito aceita tags e entra no filtro #tag (docs, links, grupos, tópicos, ideias e os conceitos novos).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/|^schema/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
core = {f: open(f).read() for f in glob.glob("Sources/VibeDeckCore/*.swift")}
def struct_body(name):
    for f, s in core.items():
        m = re.search(r"public struct %s\b[^{]*\{" % name, s)
        if m:
            i, depth = m.end(), 1
            while depth and i < len(s):
                depth += {"{": 1, "}": -1}.get(s[i], 0); i += 1
            return f, s[m.start():i], s[:m.start()].count("\n") + 1
    return None, None, None
# Conceitos: registros de arquivo próprio (SlugRecord), entidades com autoria de primeiro nível, Link e DocInfo.
# Ficam de fora partes de outro conceito (Rule de um tópico, ReviewItem de um grupo) e históricos (RuleCheck).
concepts = set(re.findall(r"extension (\w+): SlugRecord", core["Sources/VibeDeckCore/ProjectStore.swift"]))
for f, s in core.items():
    for m in re.finditer(r"public struct (\w+)\b[^{]*\{", s):
        _, body, _ = struct_body(m.group(1))
        if body and re.search(r"public var author: Author", body): concepts.add(m.group(1))
concepts |= {"Link", "DocInfo"}
concepts -= {"Rule", "ReviewItem", "RuleCheck"}
for name in sorted(concepts):
    f, body, line = struct_body(name)
    if body is None: fail(f"struct {name} não encontrada"); continue
    if not re.search(r"public var tags: \[String\]", body):
        fail(f"{f}:{line}: conceito {name} não tem tags")
# Filtro #tag: cada seção da lista entrega tags às linhas e permite editá-las.
pm = open("Sources/VibeDeckApp/ProjectModel.swift").read()
rows = re.search(r"func rows\(for section: SidebarSection\).*?\n    \}\n", pm, re.S)
if not rows: fail("Sources/VibeDeckApp/ProjectModel.swift: rows(for:) não encontrado")
else:
    for m in re.finditer(r"SectionRow\(id: \.(\w+)\(.*?\)\s*\n\s*\}", rows.group(0), re.S):
        if "tags:" not in m.group(0): fail(f"Sources/VibeDeckApp/ProjectModel.swift: linhas de .{m.group(1)} sem tags (fora do filtro #tag)")
    st = re.search(r"func setTags\(.*?\n    \}\n", pm, re.S)
    for kind in sorted(set(re.findall(r"SectionRow\(id: \.(\w+)\(", rows.group(0)))):
        if not st or f"case .{kind}(" not in st.group(0):
            fail(f"Sources/VibeDeckApp/ProjectModel.swift: setTags não edita tags de .{kind}")
sl = open("Sources/VibeDeckApp/SectionListView.swift").read()
if not re.search(r"\.searchable\(text: \$search, tokens: \$tokens", sl) or "#tag" not in sl:
    fail("Sources/VibeDeckApp/SectionListView.swift: lista sem filtro por #tag")
lv = open("Sources/VibeDeckApp/LinksView.swift").read()
if not re.search(r"\.tags\.contains", lv): fail("Sources/VibeDeckApp/LinksView.swift: links não filtráveis por tag")
# Schemas dos conceitos descrevem tags.
for sf in sorted(glob.glob("schema/v1/*.schema.json")):
    if re.search(r"(rule-check|workflow-run)\.schema\.json$", sf): continue
    if '"tags"' not in open(sf).read(): fail(f"{sf}: schema sem tags")
sys.exit(bad)
PY
