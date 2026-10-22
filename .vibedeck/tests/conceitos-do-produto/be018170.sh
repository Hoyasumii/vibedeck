#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Item de revisão sempre pertence a um grupo (reviews/<slug>.json) e o kind vem de reviewKinds.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^(Sources|crates)/|^schema/" >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
# Core Rust: itens só nascem em reviews::add_item_to_group (kind validado contra project.review_kinds) e gravam no arquivo do grupo.
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f or f.endswith("model/review_group.rs"): continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if re.search(r"\bReviewItem::new\(", l) and not l.strip().startswith("//") and not f.endswith("reviews/mod.rs"):
            fail(f"{f}:{i+1}: item criado fora de reviews::add_item_to_group (sem grupo/validação de kind): {l.strip()}")
rv = strip_tests(open("crates/vibedeck-core/src/reviews/mod.rs").read())
m = re.search(r"fn check_kind\(.*?\n\}", rv, re.S)
if not m or "review_kinds" not in m.group(0) or "UnknownKind" not in m.group(0) and "Kind desconhecido" not in rv:
    fail("crates/vibedeck-core/src/reviews/mod.rs: check_kind deve validar o kind contra project.review_kinds")
m = re.search(r"pub fn add_item\(.*?\n\}", rv, re.S)
if not m or "check_kind(" not in m.group(0) or "add_item_to_group" not in rv:
    fail("crates/vibedeck-core/src/reviews/mod.rs: criação de item deve validar o kind e apontar para um grupo (add_item_to_group)")
if "update_item" in rv and rv.count("check_kind(") < 2:
    fail("crates/vibedeck-core/src/reviews/mod.rs: update de item com novo kind deve validar contra reviewKinds")
st = open("crates/vibedeck-core/src/store.rs").read()
if not re.search(r"ReviewGroup,\s*\"reviews\"|DIR:\s*&'static str\s*=\s*\"reviews\"", st) and '"reviews"' not in st:
    fail("crates/vibedeck-core/src/store.rs: ReviewGroup deve viver em .vibedeck/reviews/<slug>.json")
# Schema do grupo descreve itens com kind, priority (low/normal/high), target, author, rules.
for sf in glob.glob("schema/**/review-group*.json", recursive=True):
    s = open(sf).read()
    for key in ('"kind"', '"priority"', '"target"', '"author"', '"rules"', '"low"', '"normal"', '"high"'):
        if key not in s: fail(f"{sf}: schema do grupo de revisão sem {key}")
# App: o kind vem dos menus/pickers de project.reviewKinds, nunca de lista fixa.
rg = open("Sources/VibeDeckApp/ReviewGroupView.swift").read()
if rg.count("model.project.reviewKinds") < 2:
    fail("Sources/VibeDeckApp/ReviewGroupView.swift: kind de item não vem de project.reviewKinds")
sys.exit(bad)
PY
cargo_tests vibedeck-core kind_desconhecido_e_alvo_vazio grupo_criado_na_hora_e_busca_por_prefixo remover_item
