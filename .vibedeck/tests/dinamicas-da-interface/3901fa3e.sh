#!/usr/bin/env bash
# Sidebar: uma seção por conceito (Docs, Revisões, Regras, Ideias…), cada uma abre SectionListView filtrável (texto e #tag)
# e lista os filhos, que abrem o item no detalhe; Links tem página própria filtrável.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/VibeDeckApp/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys
A = "Sources/VibeDeckApp/"
def read(f): return open(A + f).read()
pm, pw, sl, lv = read("ProjectModel.swift"), read("ProjectWindow.swift"), read("SectionListView.swift"), read("LinksView.swift")
bad = 0
def fail(where, msg):
    global bad; print(f"{A}{where}: {msg}"); bad = 1

def block(src, sig):
    """Corpo (chaves balanceadas) a partir da primeira linha que casa com sig."""
    m = re.search(sig, src)
    if not m: return None
    i = src.index("{", m.start()); d = 0
    for j in range(i, len(src)):
        d += {"{": 1, "}": -1}.get(src[j], 0)
        if d == 0: return src[i:j + 1]
    return None

enum = block(pm, r"enum SidebarSection\b")
if not enum: fail("ProjectModel.swift", "enum SidebarSection ausente"); sys.exit(1)
cases = re.search(r"case ([\w, ]+)\n", enum).group(1).replace(" ", "").split(",")
for case, title in [("docs", "Docs"), ("groups", "Revisões"), ("topics", "Regras"), ("ideas", "Ideias")]:
    if case not in cases: fail("ProjectModel.swift", f"SidebarSection sem a seção .{case} ({title})")
    elif not re.search(rf'case \.{case}: "{title}"', enum): fail("ProjectModel.swift", f"seção .{case} deveria se chamar \"{title}\"")

item = lambda c: c[:-1] if c.endswith("s") else c
rows = block(pm, r"func rows\(for section: SidebarSection\)") or ""
children = block(pw, r"func children\(of section: SidebarSection\)") or ""
detail = block(pw, r"var detailContent: some View") or ""
if not children: fail("ProjectWindow.swift", "children(of:) ausente: seções sem filhos na sidebar")
for c in cases:
    if not re.search(rf"case \.{c}\b", rows): fail("ProjectModel.swift", f"rows(for:) não lista a seção .{c}")
    m = re.search(rf"case \.{c}:(.*?)(?=\n        case \.|\Z)", children, re.S)
    if not m: fail("ProjectWindow.swift", f"children(of:) não lista os filhos de .{c}"); continue
    body = m.group(1)
    if f".tag(SidebarItem.{item(c)}(" not in body: fail("ProjectWindow.swift", f"filhos de .{c} sem .tag(SidebarItem.{item(c)}(…)) — não abrem no detalhe")
    if not re.search(rf"case \.{item(c)}\(let \w+\):", detail): fail("ProjectWindow.swift", f"detailContent não abre .{item(c)}(…)")
if "ForEach(SidebarSection.allCases" not in pw: fail("ProjectWindow.swift", "sidebar não cria uma seção por SidebarSection.allCases")
if ".tag(SidebarItem.section(section))" not in pw: fail("ProjectWindow.swift", "linha da seção sem .tag(SidebarItem.section(section)) — clicar não abre a lista")
if not re.search(r"case \.section\(let section\):\s*\n\s*SectionListView\(section: section", detail):
    fail("ProjectWindow.swift", "detailContent: .section não abre SectionListView")
# Lista filtrável por texto e #tag.
if not re.search(r"\.searchable\(text: \$search, tokens: \$tokens", sl): fail("SectionListView.swift", ".searchable com texto e tokens (#tag) ausente")
rf = block(sl, r"private var rows: \[SectionRow\]") or ""
if "tokens" not in rf or "search" not in rf or "row.title" not in rf: fail("SectionListView.swift", "rows não filtra por texto e por tags")
if 'hasPrefix("#")' not in sl: fail("SectionListView.swift", "busca não reconhece #tag")
if "primaryAction:" not in sl or "onOpen(id)" not in sl: fail("SectionListView.swift", "linha da lista não abre o item (primaryAction → onOpen)")
# Links: página própria filtrável.
if ".tag(SidebarItem.links)" not in pw: fail("ProjectWindow.swift", "sidebar sem Links")
if ".searchable(" not in lv: fail("LinksView.swift", "Links sem filtro (.searchable)")
sys.exit(bad)
PY
