#!/usr/bin/env bash
# Edição direta: nenhuma tela de edição tem botão Salvar (só diálogos de criação confirmam, com "Criar"),
# e toda mutação vinda da UI passa um UndoManager (undo: nil só no autosave de editores de texto, que têm undo próprio).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/VibeDeckApp/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob
bad = 0
for f in sorted(glob.glob("Sources/VibeDeckApp/*.swift")):
    lines = open(f).read().splitlines()
    func = None
    for n, l in enumerate(lines, 1):
        code = l.split("//")[0]
        m = re.match(r"\s*(?:private |fileprivate )?func (\w+)", l)
        if m: func = m.group(1)
        if re.search(r'Button\("(Salvar|Save|Aplicar|OK, salvar)"', code):
            print(f"{f}:{n}: botão \"Salvar\" — edição deve gravar na hora (e ir para o undo), sem confirmação"); bad = 1
        if re.search(r"\bundo: nil\b", code) and func != "save":
            print(f"{f}:{n}: mutação com undo: nil fora do autosave de texto — não entra no ⌘Z: {l.strip()}"); bad = 1
# Todo mutate*/change*/setTags do ProjectModel registra undo.
src = open("Sources/VibeDeckApp/ProjectModel.swift").read().splitlines()
for i, l in enumerate(src):
    m = re.match(r"\s*(?:private )?func ((?:mutate|change)\w*|setTags)\b", l)
    if not m: continue
    d, body = 0, []
    for j in range(i, len(src)):
        body.append(src[j]); d += src[j].count("{") - src[j].count("}")
        if d == 0 and "{" in "".join(body): break
    text = "\n".join(body)
    if "registerUndo" not in text and not re.search(r"\b(mutate|change|restore)\w*\(", text[text.index("{") + 1:]):
        print(f"Sources/VibeDeckApp/ProjectModel.swift:{i+1}: {m.group(1)} não registra undo"); bad = 1
sys.exit(bad)
PY
