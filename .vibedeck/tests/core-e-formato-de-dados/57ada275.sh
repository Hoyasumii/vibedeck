#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# RuleCheck.created_at com milissegundos; nome do arquivo yyyyMMdd-HHmmss-<8 do id minúsculo>.json em GMT.
applies '(^|/)crates/vibedeck-core/src/(model/(rule_check|common)|time|store)\.rs'
python3 -I - <<'PY'
import re, sys
bad = 0
def read(p): return open(p).read()
rc = read("crates/vibedeck-core/src/model/rule_check.rs")
m = re.search(r'pub struct RuleCheck \{.*?\n\}', rc, re.S)
if not m or not re.search(r'pub created_at:\s*TimestampMs', m.group(0)):
    print("crates/vibedeck-core/src/model/rule_check.rs: RuleCheck.created_at deve ser TimestampMs (com milissegundos)"); bad += 1
m = re.search(r'pub fn file_name\(&self\).*?\n    \}', rc, re.S)
body = m.group(0) if m else ""
for needle, why in [("to_lowercase()", "id em minúsculas"), (".take(8)", "8 chars do id"), ("time::check_stamp(self.created_at.0)", "carimbo yyyyMMdd-HHmmss"),
                    ('"{}-{id8}.json"', "<carimbo>-<id8>.json")]:
    if needle not in body:
        print(f"crates/vibedeck-core/src/model/rule_check.rs: RuleCheck::file_name mudou ({why})"); bad += 1
cm = read("crates/vibedeck-core/src/model/common.rs")
m = re.search(r'impl Serialize for TimestampMs.*?\n\}', cm, re.S)
if not m or "format_iso_millis" not in m.group(0):
    print("crates/vibedeck-core/src/model/common.rs: TimestampMs deve serializar com time::format_iso_millis"); bad += 1
tm = read("crates/vibedeck-core/src/time.rs")
for needle, why in [("SecondsFormat::Millis", "3 dígitos de fração"), ('"%Y%m%d-%H%M%S"', "formato do carimbo do nome do arquivo"), ("Utc", "fuso GMT/UTC")]:
    if needle not in tm:
        print(f"crates/vibedeck-core/src/time.rs: perdeu {why} ({needle})"); bad += 1
st = read("crates/vibedeck-core/src/store.rs")
if "check.file_name()" not in st or "Error::CheckExists" not in st:
    print("crates/vibedeck-core/src/store.rs: save_check deve gravar em RuleCheck::file_name() sem reescrever existentes"); bad += 1
if "items.sort_by" not in st or "b.1.check.created_at" not in st:
    print("crates/vibedeck-core/src/store.rs: checks() deve ordenar do mais novo ao mais antigo por created_at (milissegundos)"); bad += 1
sys.exit(1 if bad else 0)
PY
