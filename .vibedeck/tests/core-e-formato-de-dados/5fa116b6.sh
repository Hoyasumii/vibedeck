#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Store só tem `root` como campo; nada de cache/RefCell/Mutex/memoização nem `&mut self` nos métodos de `impl Store`.
applies '(^|/)crates/vibedeck-core/src/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
f = "crates/vibedeck-core/src/store.rs"
src = open(f).read()
m = re.search(r'pub struct Store \{(.*?)\n\}', src, re.S)
if not m:
    print(f"{f}: 'pub struct Store' não encontrado"); sys.exit(1)
fields = re.findall(r'^\s*(?:pub(?:\([^)]*\))?\s+)?(\w+)\s*:\s*([^,\n]+)', re.sub(r'//[^\n]*', '', m.group(1)), re.M)
if [n for n, _ in fields] != ["root"]:
    print(f"{f}: Store só pode guardar `root`; achei campos: {[n for n, _ in fields]}"); bad += 1
for n, t in fields:
    if re.search(r'\b(RefCell|Cell|Mutex|RwLock|OnceCell|OnceLock|LazyLock|HashMap|BTreeMap|Arc|Rc)\b', t):
        print(f"{f}: campo '{n}: {t.strip()}' é estado compartilhado/cache no Store"); bad += 1
if re.search(r'^static mut\b', src, re.M):
    print(f"{f}: 'static mut' é estado global mutável"); bad += 1
for g in sorted(glob.glob("crates/vibedeck-core/src/**/*.rs", recursive=True)):
    s = open(g).read()
    s = s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
    for im in re.finditer(r'^impl(?:<[^>]*>)? Store\b[^{]*\{', s, re.M):
        end = s.find("\n}\n", im.end())
        body = s[im.end(): end if end >= 0 else len(s)]
        for mm in re.finditer(r'fn (\w+)[^{;]*&mut self', body):
            print(f"{g}: `impl Store` com método &mut self: {mm.group(1)}"); bad += 1
sys.exit(1 if bad else 0)
PY
