#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Busca por prefixo de UUID só nos helpers (slug::resolve, match_rule, find_review_item), com >= 4 chars.
applies '(^|/)crates/vibedeck-core/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
ALLOWED = {"resolve", "match_rule", "find_review_item", "find_item"}
# Remoção por prefixo (links/claude/padrões) e o find_rule de docs/groups.rs têm contrato próprio (não são "busca de referência").
ALLOWED_AT = {("project/links.rs", "remove"), ("project/claude.rs", "remove"), ("stack/patterns.rs", "pattern_index"), ("docs/groups.rs", "find_rule"), ("workflows/ops.rs", "resolve_run_ref")}
for f in sorted(glob.glob("crates/vibedeck-core/src/**/*.rs", recursive=True)):
    src = open(f).read()
    src = src[:src.find("#[cfg(test)]")] if "#[cfg(test)]" in src else src
    lines = src.split("\n")
    for n, l in enumerate(lines):
        if l.strip().startswith("//") or not re.search(r'to_lowercase\(\)\s*\.starts_with\(|\bid[^\n]*\.starts_with\(&needle\)', l): continue
        if "id" not in l and "Id" not in l and "uuid" not in l.lower(): 
            # o filter pode estar quebrado em linhas: olha a vizinhança
            if not any("id" in x for x in lines[max(0, n - 2):n + 1]): continue
        fn = next((re.search(r'fn (\w+)', lines[k]).group(1) for k in range(n, -1, -1) if re.search(r'\bfn \w+', lines[k])), "?")
        if fn not in ALLOWED and (f.split("src/", 1)[1], fn) not in ALLOWED_AT:
            print(f"{f}:{n+1}: busca por prefixo de id reimplementada em '{fn}'; reutilize slug::resolve/match_rule/find_review_item"); bad += 1
def body(path, name):
    s = open(path).read()
    m = re.search(r'fn %s\b.*?\n\}\n' % name, s, re.S)
    return m.group(0) if m else ""
checks = {
    ("crates/vibedeck-core/src/slug.rs", "resolve"): ["c.slug == reference", "last_component(&c.slug) == made", "chars().count() >= 4", "eq_ci(&c.title, reference)",
                                                       "ambiguous(reference, prefixed)", "exists_path(reference)"],
    ("crates/vibedeck-core/src/rules/topics.rs", "match_rule"): ["chars().count() >= 4", "RuleError::RuleNotFound", "RuleError::AmbiguousRule"],
    ("crates/vibedeck-core/src/rules/topics.rs", "find_review_item"): ["chars().count() >= 4", "AmbiguousItem", "ItemNotFound"],
    ("crates/vibedeck-core/src/reviews/mod.rs", "find_item"): ["chars().count() >= 4", "Error::AmbiguousItem", "Error::ItemNotFound"],
}
for (p, fn), needles in checks.items():
    b = body(p, fn)
    if not b: print(f"{p}: função {fn} não encontrada"); bad += 1; continue
    for s in needles:
        if s not in b:
            print(f"{p}: {fn} perdeu o comportamento '{s}'"); bad += 1
sys.exit(1 if bad else 0)
PY
cargo_tests vibedeck-core resolve_variants ambiguous_prefix grupo_criado_na_hora_e_busca_por_prefixo
