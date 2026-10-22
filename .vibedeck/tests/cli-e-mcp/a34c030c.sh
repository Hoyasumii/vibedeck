#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^crates/vibedeck/"; then exit 77; fi
python3 -I - <<'PY'
import glob, re, sys
src = open("crates/vibedeck/src/mcp/instructions.rs").read()
body = re.search(r'format!\(\s*"((?:[^"\\]|\\.)*)"\s*\)', src, re.S)
if not body: sys.exit("mcp/instructions.rs: format! das instructions não encontrado")
# semântica de string Rust: `\` + newline engole o espaço seguinte; \n e \" viram caracteres
text = re.sub(r"\\\n\s*", "", body.group(1)).replace("\\n", "\n").replace('\\"', '"')
text = re.sub(r"\s+", " ", text)
tools = "\n".join(open(f).read() for f in glob.glob("crates/vibedeck/src/mcp/tools/*.rs"))
def desc(n):
    m = re.search(r'Tool::new\(\s*"%s",\s*"((?:[^"\\]|\\.)*)"' % n, tools)
    return m.group(1) if m else ""
bad = []
for p in ["REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras",
          "chame rules_for com os arquivos que você alterou",
          "chame submit_rule_check (results=[]): ele roda os scripts das regras sozinho",
          "verify_manual=true respondendo pass/fail/na para TODAS",
          "se passed=false, corrija e envie outro check"]:
    if p not in text: bad.append(f"instructions: texto obrigatório ausente: {p}")
if "OBRIGATÓRIO antes de concluir uma tarefa" not in desc("rules_for"): bad.append("rules_for: falta \"OBRIGATÓRIO antes de concluir uma tarefa\"")
if "Com verify_manual=true, responda TODAS as manuais em results" not in desc("submit_rule_check"): bad.append("submit_rule_check: falta \"Com verify_manual=true, responda TODAS as manuais em results\"")
if bad: print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
