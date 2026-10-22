#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Serialize: opcionais com skip_serializing_if = "Option::is_none" (ou opt_str_empty); tags/paths/coleções opcionais só se não vazios.
applies '(^|/)crates/vibedeck-core/src/model/'
python3 -I - <<'PY'
import glob, re, sys
# Coleções que o schema/Swift sempre gravam (mesmo vazias): arrays obrigatórios do arquivo.
ALWAYS = {"links", "items", "rules", "results", "files", "topics", "warnings", "failures", "steps", "review_kinds", "options"}
bad = 0
for f in sorted(glob.glob("crates/vibedeck-core/src/model/*.rs")):
    s = open(f).read()
    s = s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
    for m in re.finditer(r'((?:[ \t]*#\[[^\n]*\]\n)+)[ \t]*(?:pub )?struct (\w+)\s*\{', s):
        attrs, name = m.groups()
        if not re.search(r'derive\([^)]*Serialize', attrs): continue
        i, depth = m.end(), 1
        while depth and i < len(s):
            depth += {"{": 1, "}": -1}.get(s[i], 0); i += 1
        pend = ""
        for line in s[m.end():i - 1].split("\n"):
            t = line.strip()
            if t.startswith("#["): pend += t; continue
            if not t or t.startswith("//"): continue
            fm = re.match(r'(?:pub )?(\w+):\s*(.+?),?$', t)
            if fm:
                n, ty = fm.groups()
                ln = s[:m.start()].count("\n") + 1
                if "skip_serializing_if" not in pend and "skip_serializing" not in pend:
                    if ty.startswith("Option<"):
                        print(f"{f}:{ln}: {name}.{n} é opcional; use skip_serializing_if = \"Option::is_none\""); bad += 1
                    elif n in ("tags", "paths") :
                        print(f"{f}:{ln}: {name}.{n} vazio deve ser omitido (skip_serializing_if = \"vec_empty\")"); bad += 1
            pend = ""
sys.exit(1 if bad else 0)
PY
cargo_tests vibedeck-core unknown_keys_are_dropped every_managed_json_roundtrips
