#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Structs de leitura (derive Deserialize, ou *Wire quando há `from =`) só exigem os campos essenciais; o resto tem #[serde(default...)].
applies '(^|/)crates/vibedeck-core/src/model/'
python3 -I - <<'PY'
import glob, re, sys
# Campos essenciais (sem eles o registro não faz sentido). Campo novo obrigatório deve virar `default`/`nd`.
ESSENTIAL = {"title", "name", "url", "text",                       # modelos principais
             "id", "label", "icon", "kind", "status", "provider",   # ids/catálogos, enums de registros que só nascem completos
             "topic", "rule_id", "verdict", "mode", "rule_hash", "generated_at",   # resposta/teste de regra
             "step", "to", "output", "completed", "question", "number", "workflow", "cycle"}  # workflows/execuções
bad = 0
for f in sorted(glob.glob("crates/vibedeck-core/src/model/*.rs")):
    s = open(f).read()
    s = s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
    for m in re.finditer(r'((?:[ \t]*#\[[^\n]*\]\n)+)[ \t]*(?:pub )?struct (\w+)\s*\{', s):
        attrs, name = m.groups()
        if not re.search(r'derive\([^)]*Deserialize', attrs) or "from =" in attrs: continue
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
                if not ty.startswith("Option<") and "default" not in pend and n not in ESSENTIAL:
                    line_no = s[:m.start()].count("\n") + 1
                    print(f"{f}:{line_no}: {name}.{n} é obrigatório; use #[serde(default, deserialize_with = \"nd\")] (decodeIfPresent ?? default)"); bad += 1
            pend = ""
sys.exit(1 if bad else 0)
PY
cargo_tests vibedeck-core null_counts_as_absent project_children_defaults idea_readiness_dependencies_and_defaults rule_topic_author_and_rule_test rule_check_milliseconds_and_defaults
