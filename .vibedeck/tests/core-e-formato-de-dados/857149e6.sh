#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Toda escrita de registro passa por store::write_atomic (a única que cria arquivo: temp no mesmo diretório + rename).
applies '(^|/)crates/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
pat = re.compile(r'\bfs::write\(|\bFile::create(?:_new)?\(|\bOpenOptions\b|\bfs::copy\(|\bfs::rename\(')
# Fora do store: log da máquina em append (logs.rs), mover pasta de docs (rename) e marcas de estado do hook em tmp.
ALLOWED = {"crates/vibedeck-core/src/store.rs", "crates/vibedeck-core/src/project/logs.rs",
           "crates/vibedeck-core/src/docs/groups.rs", "crates/vibedeck/src/cli/rules.rs"}
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f or f in ALLOWED: continue
    s = open(f).read()
    if "#[cfg(test)]" in s: s = s[:s.find("#[cfg(test)]")]
    for n, l in enumerate(s.split("\n"), 1):
        if l.strip().startswith("//"): continue
        if pat.search(l):
            print(f"{f}:{n}: escrita direta fora de store::write_atomic: {l.strip()}"); bad += 1
src = open("crates/vibedeck-core/src/store.rs").read()
m = re.search(r'pub fn write_atomic\(.*?\n\}\n', src, re.S)
b = m.group(0) if m else ""
for needle, why in [("create_dir_all(parent)", "criar o diretório pai"), ("create_new(&tmp)", "temp exclusivo no mesmo diretório"),
                    ("sync_all()", "fsync antes do rename"), ("fs::rename(&tmp, &target)", "rename atômico")]:
    if needle not in b:
        print(f"crates/vibedeck-core/src/store.rs: write_atomic perdeu '{why}' ({needle})"); bad += 1
sys.exit(1 if bad else 0)
PY
