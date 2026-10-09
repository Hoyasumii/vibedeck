#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Item de revisão sempre pertence a um grupo (reviews/<slug>.json) e o kind vem de reviewKinds.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/|^schema/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def block(lines, i):
    """Bloco do case/func que contém a linha i (até o próximo case/func no mesmo nível)."""
    start = i
    while start > 0 and not re.match(r"\s*(case \"|func |struct )", lines[start]): start -= 1
    end = i + 1
    while end < len(lines) and not re.match(r"\s*(case \"|func |struct )", lines[end]): end += 1
    return "\n".join(lines[start:end])
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    lines = open(f).read().split("\n")
    for i, l in enumerate(lines):
        if l.strip().startswith("//"): continue
        creates = re.search(r"\bReviewItem\(", l) and "struct ReviewItem" not in l
        sets_kind = re.search(r"\bitem\.kind = |\$0\.kind = ", l)
        if not (creates or sets_kind): continue
        b = block(lines, i)
        if f.startswith("Sources/VibeDeckApp/"):
            # No app o kind vem dos menus/pickers de model.project.reviewKinds.
            if "reviewKinds" not in b and "kind.id" not in b and "newKind" not in b:
                fail(f"{f}:{i+1}: kind de item não vem de project.reviewKinds")
        elif f.startswith("Sources/vibedeck/") or f.startswith("Sources/VibeDeckCore/"):
            if f.endswith("Models.swift"): continue
            if "reviewKinds" not in b:
                fail(f"{f}:{i+1}: kind de item gravado sem validar contra reviewKinds: {l.strip()}")
        if creates and f.startswith("Sources/vibedeck/") and not re.search(r"addItem\(\w+, toGroup:", b):
            fail(f"{f}:{i+1}: item criado sem apontar para um grupo (addItem toGroup)")
        if creates and f.startswith("Sources/VibeDeckApp/") and not re.search(r"mutateGroup\(|addItem\(", b):
            fail(f"{f}:{i+1}: item criado fora de um grupo")
# Itens só são gravados dentro do arquivo do grupo.
store = open("Sources/VibeDeckCore/ProjectStore.swift").read()
if not re.search(r'func groupURL\(_ slug: String\) -> URL \{ reviewsDir\.appending\(path: "\\\(slug\)\.json"\) \}', store):
    fail("Sources/VibeDeckCore/ProjectStore.swift: groupURL não é reviews/<slug>.json")
# Schema do grupo descreve itens com kind, priority (low/normal/high), target, author, rules.
for sf in glob.glob("schema/**/review-group*.json", recursive=True):
    s = open(sf).read()
    for key in ('"kind"', '"priority"', '"target"', '"author"', '"rules"', '"low"', '"normal"', '"high"'):
        if key not in s: fail(f"{sf}: schema do grupo de revisão sem {key}")
sys.exit(bad)
PY
