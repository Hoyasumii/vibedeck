#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Checks são histórico imutável: só submitCheck grava (arquivo novo), nada edita nem apaga.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
STORE = "Sources/VibeDeckCore/ProjectStore.swift"
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    lines = open(f).read().split("\n")
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith("//"): continue
        # Uso de checksDir: só definição, criação do diretório, gravação nova no submitCheck e leitura.
        if "checksDir" in l:
            ok = (f == STORE and (
                re.search(r"public var checksDir", l)
                or re.search(r"for dir in \[.*checksDir", l)
                or "checksDir.appending(path: Self.checkFileName(check))" in l
                or re.search(r"fileExists\(atPath: checksDir\.path\)", l)
                or re.search(r"contentsOfDirectory\(at: checksDir", l)))
            if not ok: fail(f"{f}:{i+1}: uso de checksDir fora da gravação/leitura permitida: {s}")
        if re.search(r"\b(removeItem|trashItem|moveItem|replaceItem)\b.*check", l, re.I):
            fail(f"{f}:{i+1}: apaga/move arquivo de check: {s}")
        # O helper privado cria um RuleCheck novo; não recebe um check existente para alteração.
        creates_new = f == STORE and s.startswith("private func saveRuleCheck(task:")
        if re.search(r"func (update|delete|remove|edit|save|trash)\w*Check", l) and not creates_new:
            fail(f"{f}:{i+1}: operação de alteração de check: {s}")
        if re.search(r'Tool\(name: "(update|delete|remove|edit)_\w*check', l):
            fail(f"{f}:{i+1}: ferramenta MCP altera checks: {s}")
        if re.search(r'"(?:checks|check)/', l) or re.search(r'appending\(path: "checks"', l) and f != STORE:
            fail(f"{f}:{i+1}: caminho de checks montado à mão: {s}")
# submitCheck grava em nome novo (data + id), com escrita única.
src = open(STORE).read()
helper = re.search(r"private func saveRuleCheck\(.*?\n    \}", src, re.S)
if helper and ("let check = RuleCheck(" not in helper.group(0)
               or "checksDir.appending(path: Self.checkFileName(check))" not in helper.group(0)):
    fail(f"{STORE}: saveRuleCheck deve criar um registro novo com nome derivado de seu id")
if src.count("VDJSON.encode(check)") != 1:
    fail(f"{STORE}: RuleCheck deve ser gravado em um único ponto (submitCheck)")
m = re.search(r"func checkFileName\(.*?\n    \}", src, re.S)
if not m or "check.id" not in m.group(0):
    fail(f"{STORE}: checkFileName não inclui o id do check (arquivo novo a cada submit)")
sys.exit(bad)
PY
