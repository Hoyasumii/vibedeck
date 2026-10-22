#!/usr/bin/env bash
# V2: o trilho tem um espaço por área (Planejar, Automação, Qualidade, Projeto); cada conceito aparece na coluna de
# conteúdo de um espaço com lista filtrável e abre o item no detalhe.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -E '^Sources/VibeDeckApp/' >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, sys
A = "Sources/VibeDeckApp/"
def read(f): return open(A + f).read()
nav, win, col, pm = read("V2/V2Navigation.swift"), read("V2/V2ProjectWindow.swift"), read("V2/V2ContentColumn.swift"), read("ProjectModel.swift")
bad = 0
def fail(where, msg):
    global bad; print(f"{A}{where}: {msg}"); bad = 1
def block(src, sig):
    m = re.search(sig, src)
    if not m: return ""
    i = src.index("{", m.start()); d = 0
    for j in range(i, len(src)):
        d += {"{": 1, "}": -1}.get(src[j], 0)
        if d == 0: return src[i:j + 1]
    return ""
space = block(nav, r"enum V2Space\b")
concept = block(nav, r"enum V2Concept\b")
spaces = re.search(r"case (plan[\w, ]*)\n", space)
if not spaces or spaces.group(1).replace(" ", "").split(",") != ["plan", "automation", "quality", "project"]:
    fail("V2/V2Navigation.swift", "o trilho deve ter Planejar, Automação, Qualidade e Projeto")
for title in ["Planejar", "Automação", "Qualidade", "Projeto"]:
    if f'return "{title}"' not in space: fail("V2/V2Navigation.swift", f"espaço {title} sem título")
cases = re.search(r"case (ideas[\w, ]*)\n(?:\s*case ([\w, ]+)\n)*", concept)
all_cases = []
for m in re.finditer(r"^\s*case ((?:\w+)(?:, \w+)*)\s*$", concept.split("var id")[0], re.M):
    all_cases += m.group(1).replace(" ", "").split(",")
listed = re.findall(r"return \[((?:\.\w+(?:, )?)+)\]", space)
in_spaces = set(x.strip(". ") for l in listed for x in l.split(","))
for c in all_cases:
    if c not in in_spaces: fail("V2/V2Navigation.swift", f"conceito .{c} não aparece em nenhum espaço do trilho")
need = ["ideas", "docs", "references", "agents", "commands", "skills", "workflows", "rules", "reviews", "history", "project"]
for c in need:
    if c not in all_cases: fail("V2/V2Navigation.swift", f"conceito .{c} ausente")
# Páginas do Projeto e das Referências.
for p in ["overview", "stack", "patterns", "graph", "integrations", "usage", "links", "claudeItems", "checksHistory"]:
    if not re.search(rf"case \.{p}\b", nav): fail("V2/V2Navigation.swift", f"página .{p} ausente")
# Toda seção (SidebarSection) tem conceito e lista filtrável (SectionRow) na coluna de conteúdo.
sec = block(pm, r"enum SidebarSection\b")
sections = re.search(r"case ([\w, ]+)\n", sec).group(1).replace(" ", "").split(",")
fs = block(nav, r"static func forSection")
rows = block(pm, r"func rows\(for section: SidebarSection\)")
for s in sections:
    if not re.search(rf"case \.{s}: return \.", fs): fail("V2/V2Navigation.swift", f"forSection não mapeia a seção .{s}")
    if not re.search(rf"case \.{s}\b", rows): fail("ProjectModel.swift", f"rows(for:) não lista a seção .{s}")
if "model.rows(for:" not in col and "model.rows(for: $0)" not in col: fail("V2/V2ContentColumn.swift", "coluna sem as linhas da seção (model.rows(for:))")
if "private var filterField" not in col: fail("V2/V2ContentColumn.swift", "coluna de conteúdo sem filtro")
if "pageList" not in col or "sectionList" not in col: fail("V2/V2ContentColumn.swift", "coluna sem lista de seção e lista de páginas")
# Abrir no detalhe: cada item e página tem destino em V2ProjectWindow.
item = lambda c: c[:-1] if c.endswith("s") else c
for s in sections:
    it = item(s)
    if not re.search(rf"case \.{it}\(let \w+\)", win): fail("V2/V2ProjectWindow.swift", f"detalhe não abre .{it}(…)")
for p in ["stack", "patterns", "links", "claudeItems", "graph", "integrations", "usage", "checksHistory"]:
    if not re.search(rf"case \.{p}:", win): fail("V2/V2ProjectWindow.swift", f"detalhe não abre a página .{p}")
if not re.search(r"case \.section\(let section\):\s*\n\s*sectionTable\(section\)", win): fail("V2/V2ProjectWindow.swift", ".section não abre a tabela (SectionListView)")
if "V2OverviewView" not in win: fail("V2/V2ProjectWindow.swift", "Projeto sem Visão geral")
if ".onTapGesture" in col and "selection" not in col: fail("V2/V2ContentColumn.swift", "itens da lista não abrem no detalhe")
if "List(rows, selection: $selection)" not in col: fail("V2/V2ContentColumn.swift", "linhas da lista não abrem o item no detalhe (List selection)")
sys.exit(bad)
PY
