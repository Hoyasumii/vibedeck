#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Atalhos documentados: presença no lugar certo e sem reuso das combinações para outra coisa.
chk() { grep -qE "$2" "$1" || bad "$1" "$3"; }
chk Sources/VibeDeckApp/VibeDeckApp.swift 'keyboardShortcut\("o"\)' "⌘O (Abrir Projeto…) ausente"
chk Sources/VibeDeckApp/MarkdownPreview.swift 'keyboardShortcut\("e"\)' "⌘E (alternar editar/ler) ausente"
chk Sources/VibeDeckApp/ReviewGroupView.swift 'keyboardShortcut\("n", modifiers: \[\.command, \.shift\]\)' "⇧⌘N (novo item de revisão) ausente"
for f in ReviewGroupView IdeaView RulesView AgentView CommandView SkillView WorkflowView; do
  chk Sources/VibeDeckApp/$f.swift 'keyboardShortcut\("i", modifiers: \[\.command, \.option\]\)' "⌥⌘I (painel do item) ausente"
done
python3 -I - <<'PY' || fail=1
import re, glob, sys
bad = 0
for f in sorted(glob.glob("Sources/VibeDeckApp/*.swift")):
    lines = open(f).read().splitlines()
    for i, l in enumerate(lines):
        code = l.split("//")[0]
        m = re.search(r'keyboardShortcut\("(\w)"(?:, modifiers: (\S.*?))?\)', code)
        if not m: continue
        key, mods = m.group(1), (m.group(2) or "")
        if key == "z":
            print(f"{f}:{i+1}: ⌘Z/⇧⌘Z pertencem ao undo/redo do sistema"); bad = 1
        elif key == "o" and not mods and not f.endswith("VibeDeckApp.swift"):
            print(f"{f}:{i+1}: ⌘O reservado para Abrir Projeto"); bad = 1
        elif key == "e" and not mods and not f.endswith("MarkdownPreview.swift"):
            print(f"{f}:{i+1}: ⌘E reservado para alternar editar/ler"); bad = 1
        elif key == "n" and ".command" in mods and ".shift" in mods and not re.search(r'(ReviewGroupView|RulesView)\.swift$', f):
            print(f"{f}:{i+1}: ⇧⌘N reservado para foco do campo de novo item"); bad = 1
        elif key == "i" and ".command" in mods and ".option" in mods:
            ctx = "\n".join(lines[max(0, i-3):i+1])
            if not re.search(r'\.toggle\(\)', ctx):
                print(f"{f}:{i+1}: ⌥⌘I deve mostrar/ocultar o painel (esperava .toggle() no botão)"); bad = 1
sys.exit(bad)
PY
exit $fail
