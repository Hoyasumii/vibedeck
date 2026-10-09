#!/usr/bin/env bash
# Item de revisão: open → in_progress → done | wontfix; done e wontfix são fechados (isClosed);
# telas e filtros usam isClosed, a lista separa Abertos/Concluídos e permite reabrir.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/|^schema/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
m = open("Sources/VibeDeckCore/Models.swift").read()
if not re.search(r"enum ReviewStatus: String[^{]*\{\s*case open, inProgress = \"in_progress\", done, wontfix\s*\n", m):
    fail("Sources/VibeDeckCore/Models.swift: ReviewStatus deve ter exatamente open, in_progress, done, wontfix")
if "public var isClosed: Bool { self == .done || self == .wontfix }" not in m:
    fail("Sources/VibeDeckCore/Models.swift: ReviewStatus.isClosed deve ser done || wontfix")
s = open("schema/v1/review-group.schema.json").read()
if not re.search(r'"status":\s*\{\s*"enum":\s*\["open",\s*"in_progress",\s*"done",\s*"wontfix"\]', s):
    fail("schema/v1/review-group.schema.json: status deve ser open | in_progress | done | wontfix")
# Filtros/contagens de itens de revisão decidem aberto/fechado por isClosed, não comparando status.
REVIEW_VARS = r"(?:item|i|it|\$0|\$1|entry\.value|reviewItem)"
FILTERING = re.compile(r"\.(filter|count|first|contains|allSatisfy|partition|sorted|drop|prefix)\b|where:|\bwhere\b|guard |if ")
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    if f.endswith("Models.swift"): continue
    src = open(f).read()
    if "ReviewItem" not in src and "ReviewGroup" not in src and "items" not in src: continue
    for i, l in enumerate(src.split("\n")):
        if l.strip().startswith("//"): continue
        for mm in re.finditer(REVIEW_VARS + r"\.status\s*(==|!=)\s*\.(done|wontfix)\b", l):
            if not FILTERING.search(l): continue  # apresentação (ícone/cor) pode distinguir done de wontfix
            if re.search(r"\b(run|idea|workflow|r)\.status", l): continue
            fail(f"{f}:{i+1}: aberto/fechado decidido sem isClosed: {l.strip()}")
# Lista do grupo: Abertos / Concluídos via isClosed e botão de reabrir.
v = open("Sources/VibeDeckApp/ReviewGroupView.swift").read()
if not re.search(r'case open = "Abertos", closed = "Concluídos"', v): fail("Sources/VibeDeckApp/ReviewGroupView.swift: falta o filtro Abertos/Concluídos")
if "case .open: !$0.status.isClosed" not in v or "case .closed: $0.status.isClosed" not in v:
    fail("Sources/VibeDeckApp/ReviewGroupView.swift: filtro Abertos/Concluídos não usa isClosed")
if "Reabrir" not in v or not re.search(r"status\.isClosed \? \.open", v):
    fail("Sources/VibeDeckApp/ReviewGroupView.swift: item fechado não pode ser reaberto")
# Seletores de status mostram os quatro status (ForEach em ReviewStatus.allCases), MCP/CLI aceitam todos.
if not re.search(r"ReviewStatus\.allCases", v): fail("Sources/VibeDeckApp/ReviewGroupView.swift: seletor de status não lista os quatro status")
mcp = open("Sources/vibedeck/MCPServer.swift").read()
if not re.search(r"statuses = ReviewStatus\.allCases", mcp): fail("Sources/vibedeck/MCPServer.swift: enum de status do MCP não vem de ReviewStatus.allCases")
sys.exit(bad)
PY
