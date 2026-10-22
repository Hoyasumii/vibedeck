#!/usr/bin/env bash
# Heurística: literais de texto visível ao usuário (mensagens de erro, about/help do clap, descrições de ferramentas MCP,
# doc comments de comandos clap) adicionados no diff não podem parecer inglês (>=2 stopwords em inglês e nenhuma em português).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"

files=$(printf '%s\n' "${VIBEDECK_FILES:-}" | grep -E '^crates/.*\.rs$|^crates/vibedeck-core/src/ai/guide_reference\.md$' || true)
if [ -z "$files" ]; then
  [ -z "${VIBEDECK_FILES:-}" ] || exit 77
  files=$(git diff --name-only HEAD -- 'crates/*.rs' 'crates/vibedeck-core/src/ai/guide_reference.md' || true)
  [ -n "$files" ] || exit 0
fi

# shellcheck disable=SC2086
python3 -I - $files <<'PY'
import re, subprocess, sys

EN = set("the and to of is are for with from or an in on not this that be it as at by will can has have if when your you".split())
PT = set("o a os as de do da dos das e em um uma para com por que não se é ao aos na no nas nos ou foi ser são já mais mas como pelo pela entre sem sobre".split())
# contextos de texto visível: #[error], about/help/long_about do clap, descrição/props de ferramentas MCP, doc comments da CLI (viram help)
CTX = re.compile(r'(#\[error\(|\babout\s*=|\blong_about\s*=|\bhelp\s*=|\bprop\(|Tool::new\(|ToolError::new\(|\bformat!\()')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')

bad = 0
for f in sys.argv[1:]:
    diff = subprocess.run(["git", "diff", "-U0", "HEAD", "--", f], capture_output=True, text=True).stdout
    line = 0
    added = []
    for l in diff.splitlines():
        m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)', l)
        if m:
            line = int(m.group(1)); continue
        if l.startswith('+') and not l.startswith('+++'):
            added.append((line, l[1:])); line += 1
    in_mcp = "/mcp/" in f
    in_cli = "/cli/" in f
    for n, text in added:
        s = text.strip()
        if in_cli and s.startswith("///"):          # doc comment de item clap = texto de --help
            lits = [s[3:].strip()]
        elif s.startswith('//') or f.endswith(".md") and False:
            continue
        elif CTX.search(s) or (in_mcp and re.fullmatch(r'"(?:[^"\\]|\\.)*",?', s)):
            lits = LIT.findall(s)
        else:
            continue
        for lit in lits:
            if '{' in lit and len(lit) < 12:
                continue
            words = re.findall(r"[A-Za-zÀ-ÿ]+", lit.lower())
            en = sum(w in EN for w in words)
            pt = sum(w in PT for w in words)
            if en >= 2 and pt == 0:
                print(f"{f}:{n}: texto possivelmente em inglês: \"{lit}\"")
                bad += 1
sys.exit(1 if bad else 0)
PY
