#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# slug::make mantém suas regras; criação de registros usa Store::new_slug (slug::make + slug::unique); sem slug montado à mão.
applies '(^|/)crates/vibedeck-core/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
slug = open("crates/vibedeck-core/src/slug.rs").read()
for needle, why in [("const MAX_LEN: usize = 60", "corte em 60"), ("is_ascii_alphanumeric()", "só ASCII alfanumérico"), ("fold(text)", "sem acentos/minúsculas"),
                    ("out.push('-')", "separador -"), ('"untitled"', "fallback untitled"), ("out.truncate(MAX_LEN)", "truncar em MAX_LEN")]:
    if needle not in slug:
        print(f"crates/vibedeck-core/src/slug.rs: slug::make perdeu '{why}' ({needle})"); bad += 1
u = re.search(r'pub fn unique\(.*?\n\}', slug, re.S)
if not u or 'format!("{base}-{n}")' not in u.group(0) or "let mut n = 2" not in u.group(0):
    print("crates/vibedeck-core/src/slug.rs: slug::unique deve acrescentar -2, -3... se o arquivo existir"); bad += 1
store = open("crates/vibedeck-core/src/store.rs").read()
m = re.search(r'pub fn new_slug<.*?\n    \}\n', store, re.S)
if not m or "slug::make(title)" not in m.group(0) or "slug::unique(" not in m.group(0):
    print("crates/vibedeck-core/src/store.rs: Store::new_slug deve usar slug::unique(slug::make(título), ...)"); bad += 1
hand = re.compile(r'\.replace\(\s*(?:\' \'|" ")\s*,\s*"-"\s*\)|\.split_whitespace\(\)\.collect::<Vec<_>>\(\)\.join\("-"\)')
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f: continue
    s = open(f).read()
    if "#[cfg(test)]" in s: s = s[:s.find("#[cfg(test)]")]
    for n, l in enumerate(s.split("\n"), 1):
        if hand.search(l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: slug montado à mão; use slug::make: {l.strip()}"); bad += 1
# Criação por conceito passa por new_slug/create (ideias, tópicos, grupos, workflows, agentes/comandos/skills).
for f, needle in [("crates/vibedeck-core/src/ideas.rs", "self.create(&idea"), ("crates/vibedeck-core/src/ideas.rs", "self.new_slug::<RuleTopic>"),
                  ("crates/vibedeck-core/src/rules/topics.rs", "store.new_slug::<RuleTopic>"), ("crates/vibedeck-core/src/reviews/mod.rs", "store.create(&group"),
                  ("crates/vibedeck-core/src/workflows/ops.rs", "store.create(&wf"), ("crates/vibedeck-core/src/resources/persona.rs", "store.new_slug::<P>")]:
    if needle not in open(f).read():
        print(f"{f}: criação deve usar Store::create/new_slug ({needle})"); bad += 1
sys.exit(1 if bad else 0)
PY
cargo_tests vibedeck-core basic_make empty_becomes_untitled never_starts_with_dash_and_collapses truncates_at_60_possibly_ending_in_dash unique_adds_suffix record_slugs_match_titles
