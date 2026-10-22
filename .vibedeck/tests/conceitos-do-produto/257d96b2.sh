#!/usr/bin/env bash
# Item de revisão: open → in_progress → done | wontfix; done e wontfix são fechados (is_closed/isClosed);
# telas e filtros usam isClosed, a lista separa Abertos/Concluídos e permite reabrir.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^(Sources|crates)/|^schema/" >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
# Core Rust
rg = open("crates/vibedeck-core/src/model/review_group.rs").read()
if not re.search(r'#\[serde\(rename_all = "snake_case"\)\]\s*pub enum ReviewStatus \{\s*#\[default\]\s*Open,\s*InProgress,\s*Done,\s*Wontfix,\s*\}', rg):
    fail("crates/vibedeck-core/src/model/review_group.rs: ReviewStatus deve ter exatamente Open, InProgress, Done, Wontfix (snake_case)")
if not re.search(r"pub fn is_closed\(self\) -> bool \{\s*matches!\(self, ReviewStatus::Done \| ReviewStatus::Wontfix\)\s*\}", rg):
    fail("crates/vibedeck-core/src/model/review_group.rs: ReviewStatus::is_closed deve ser Done | Wontfix")
if '["open", "in_progress", "done", "wontfix"]' not in open("crates/vibedeck-core/src/reviews/mod.rs").read():
    fail("crates/vibedeck-core/src/reviews/mod.rs: STATUSES deve listar open, in_progress, done, wontfix")
s = open("schema/v1/review-group.schema.json").read()
if not re.search(r'"status":\s*\{\s*"enum":\s*\["open",\s*"in_progress",\s*"done",\s*"wontfix"\]', s):
    fail("schema/v1/review-group.schema.json: status deve ser open | in_progress | done | wontfix")
# Filtros do Core decidem aberto/fechado por is_closed, não comparando com Done/Wontfix.
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f or f.endswith("model/review_group.rs"): continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if l.strip().startswith("//"): continue
        if re.search(r"\b(item|i|it|r)\.status\s*(==|!=)\s*ReviewStatus::(Done|Wontfix)\b", l) and re.search(r"filter|count|any|all|find|retain|if |!|&&|\|\|", l):
            fail(f"{f}:{i+1}: aberto/fechado decidido sem is_closed: {l.strip()}")
# App Swift (modelo espelhado e telas)
m = open("Sources/VibeDeckApp/Core/Model/Models.swift").read()
if not re.search(r"enum ReviewStatus: String[^{]*\{\s*case open, inProgress = \"in_progress\", done, wontfix\s*\n", m):
    fail("Sources/VibeDeckApp/Core/Model/Models.swift: ReviewStatus deve ter exatamente open, in_progress, done, wontfix")
if "var isClosed: Bool { self == .done || self == .wontfix }" not in m:
    fail("Sources/VibeDeckApp/Core/Model/Models.swift: ReviewStatus.isClosed deve ser done || wontfix")
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
v = open("Sources/VibeDeckApp/ReviewGroupView.swift").read()
if not re.search(r'case open = "Abertos", closed = "Concluídos"', v): fail("Sources/VibeDeckApp/ReviewGroupView.swift: falta o filtro Abertos/Concluídos")
if "case .open: !$0.status.isClosed" not in v or "case .closed: $0.status.isClosed" not in v:
    fail("Sources/VibeDeckApp/ReviewGroupView.swift: filtro Abertos/Concluídos não usa isClosed")
if "Reabrir" not in v or not re.search(r"status\.isClosed \? \.open", v):
    fail("Sources/VibeDeckApp/ReviewGroupView.swift: item fechado não pode ser reaberto")
if not re.search(r"ReviewStatus\.allCases", v): fail("Sources/VibeDeckApp/ReviewGroupView.swift: seletor de status não lista os quatro status")
# MCP/CLI aceitam todos (enum vem de reviews::STATUSES)
mcp = open("crates/vibedeck/src/mcp/tools/reviews.rs").read()
if mcp.count('("status", &STATUSES)') < 2: fail("crates/vibedeck/src/mcp/tools/reviews.rs: enum de status do MCP não vem de reviews::STATUSES")
sys.exit(bad)
PY
