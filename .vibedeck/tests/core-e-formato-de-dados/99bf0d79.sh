#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# json::encode (VDJSON) é o emissor canônico dos arquivos do projeto; serde_json::to_*_pretty só em protocolos de fio.
applies '(^|/)crates/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
j = open("crates/vibedeck-core/src/json.rs").read()
j = j[:j.find("#[cfg(test)]")] if "#[cfg(test)]" in j else j
for needle, why in [("a.0.as_bytes().cmp(b.0.as_bytes())", "chaves ordenadas por bytes (sortedKeys)"), ('" : "', "separador ' : ' (prettyPrinted)"),
                    ('out.push_str("  ")', "indentação de 2 espaços"), ("out.push('\\n');", "\\n no fim"),
                    ("pub fn encode", "json::encode"), ("pub fn to_vdjson", "json::to_vdjson")]:
    if needle not in j:
        print(f"crates/vibedeck-core/src/json.rs: emissor sem {why} ({needle})"); bad += 1
if re.search(r"'/' =>|\"\\\\/\"", j):
    print("crates/vibedeck-core/src/json.rs: '/' não pode ser escapado (withoutEscapingSlashes)"); bad += 1
store = open("crates/vibedeck-core/src/store.rs").read()
if store.count("json::encode(") < 2:
    print("crates/vibedeck-core/src/store.rs: save/save_check devem gravar via json::encode"); bad += 1
# Datas: ISO 8601 UTC; leitura aceita com e sem frações.
t = open("crates/vibedeck-core/src/time.rs").read()
for fn in ("format_iso", "format_iso_millis", "parse_iso"):
    if f"pub fn {fn}" not in t:
        print(f"crates/vibedeck-core/src/time.rs: falta {fn}"); bad += 1
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f or f.endswith("crates/vibedeck-core/src/json.rs"): continue
    s = open(f).read()
    if "#[cfg(test)]" in s: s = s[:s.find("#[cfg(test)]")]
    for n, l in enumerate(s.split("\n"), 1):
        if re.search(r'serde_json::to_(string|vec|writer)_pretty\(|serde_json::ser::PrettyFormatter', l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: use json::encode/to_vdjson para arquivos do projeto: {l.strip()}"); bad += 1
if bad: sys.exit(1)
PY
cargo_tests vibedeck-core empty_containers_have_blank_line keys_sorted_by_bytes control_characters_and_escapes unicode_stays_raw dates_are_truncated_and_uuid_uppercased
