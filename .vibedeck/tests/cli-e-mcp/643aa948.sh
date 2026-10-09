#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
python3 -I - "$MCP" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split("\n")
# blocos "case \"nome\":" do handler
starts = [(i, m.group(1)) for i, l in enumerate(src) if (m := re.match(r"^\s{8}case \"([a-z_]+)\":", l))]
bad = 0
for k, (i, name) in enumerate(starts):
    end = starts[k + 1][0] if k + 1 < len(starts) else len(src)
    body = "\n".join(src[i:end])
    creates = re.search(r"\b(Rule|ReviewItem)\(|createIdea\(|addCustomPattern\(|addPatterns\(|\.add\(|import(Agents|Commands|Skills)\(", body)
    if (name.startswith(("add_", "import_")) or name == "submit_rule_check") and creates and "author: .ai" not in body:
        print(f"{sys.argv[1]}:{i+1}: ferramenta {name} cria registro sem author: .ai"); bad += 1
# descrição das ferramentas criadoras originais (add_idea_rule e submit_rule_check: só author: .ai no código)
for name in ["add_review_item", "add_rule", "add_idea"]:
    m = re.search(r"Tool\(name: \"%s\", description: \"((?:[^\"\\]|\\.)*)\"" % name, "\n".join(src))
    if not m: print(f"ferramenta {name} não encontrada"); bad += 1
    elif "author=ai" not in m.group(1): print(f"{sys.argv[1]}: descrição de {name} não diz \"author=ai\""); bad += 1
sys.exit(1 if bad else 0)
PY
