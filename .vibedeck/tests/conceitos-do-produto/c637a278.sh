#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# Checks são histórico imutável: só Store::save_check grava (arquivo novo), nada edita nem apaga.
applies '^(crates|Sources)/'
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
STORE = "crates/vibedeck-core/src/store.rs"
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f: continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        s = l.strip()
        if s.startswith("//"): continue
        # checks_dir(): só store.rs (definição, ensure_directories, leitura em checks() e gravação em save_check).
        if re.search(r"\bchecks_dir\(\)", l) and f != STORE:
            fail(f"{f}:{i+1}: uso de checks_dir fora do Store: {s}")
        if re.search(r"remove_file|remove_dir|rename|fs::copy", l) and re.search(r"check", l, re.I):
            fail(f"{f}:{i+1}: apaga/move arquivo de check: {s}")
        if re.search(r"fn (update|delete|remove|edit|trash|rewrite)\w*check", l):
            fail(f"{f}:{i+1}: operação de alteração de check: {s}")
        if re.search(r'"(update|delete|remove|edit)_\w*check\w*"', l):
            fail(f"{f}:{i+1}: ferramenta MCP altera checks: {s}")
        if re.search(r'"\.vibedeck/checks|"checks/', l) and f not in (STORE, "crates/vibedeck-core/src/rules/checklist.rs", "crates/vibedeck-core/src/rules/stopgate.rs", "crates/vibedeck-core/src/ai/reorganize.rs"):
            fail(f"{f}:{i+1}: caminho de checks montado à mão: {s}")
src = strip_tests(open(STORE).read())
m = re.search(r"pub fn save_check\(.*?\n    \}", src, re.S)
b = m.group(0) if m else ""
if "check.file_name()" not in b or "Error::CheckExists" not in b or "write_atomic" not in b:
    fail(f"{STORE}: save_check deve gravar um arquivo novo (nome do id), recusar existente (CheckExists) e usar write_atomic")
if src.count("json::encode(check)") != 1:
    fail(f"{STORE}: RuleCheck deve ser gravado em um único ponto (save_check)")
# App Swift: nenhum uso de checksDir além da declaração; nada apaga/move check.
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    for i, l in enumerate(open(f).read().split("\n")):
        s = l.strip()
        if s.startswith("//"): continue
        if "checksDir" in l and not (f == "Sources/VibeDeckApp/Core/CoreStore.swift" and re.search(r"var checksDir: URL", l)):
            fail(f"{f}:{i+1}: uso de checksDir fora da declaração: {s}")
        if re.search(r"\b(removeItem|trashItem|moveItem|replaceItem)\b.*check", l, re.I):
            fail(f"{f}:{i+1}: apaga/move arquivo de check: {s}")
sys.exit(bad)
PY
cargo_tests vibedeck-core checks_are_append_only_and_newest_first
