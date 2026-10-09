#!/usr/bin/env bash
# Inspector: Revisões (item: tipo, status, prioridade, alvo, regras), Ideias (regras + promoção) e Regras (verificações)
# têm .inspector; toda página com .inspector alterna com ⌥⌘I.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/VibeDeckApp/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{w}: {m}"); bad = 1
for f in ["ReviewGroupView.swift", "IdeaView.swift", "RulesView.swift"]:
    if not re.search(r"\.inspector\(isPresented: \$\w+\)", open(A + f).read()): fail(A + f, "página sem .inspector")
for f in sorted(glob.glob(A + "*.swift")):
    s = open(f).read()
    for m in re.finditer(r"\.inspector\(isPresented: \$(\w+)\)", s):
        v = m.group(1); n = s[:m.start()].count("\n") + 1
        if not re.search(rf"\{{ {v}\.toggle\(\) \}}[^\n]*\n\s*\.keyboardShortcut\(\"i\", modifiers: \[\.command, \.option\]\)", s):
            fail(f"{f}:{n}", f"inspector ${v} sem botão {v}.toggle() com ⌥⌘I (.keyboardShortcut(\"i\", modifiers: [.command, .option]))")
rg = open(A + "ReviewGroupView.swift").read()
insp = rg[rg.find("struct ReviewItemInspector"):]
for label in ["Tipo", "Status", "Prioridade"]:
    if f'Picker("{label}"' not in insp: fail(A + "ReviewGroupView.swift", f"inspector do item sem {label}")
if "targetField(" not in insp: fail(A + "ReviewGroupView.swift", "inspector do item sem alvo (targetField)")
if "rulesSection" not in insp: fail(A + "ReviewGroupView.swift", "inspector do item sem regras ligadas")
if "ReviewItemInspector(" not in rg: fail(A + "ReviewGroupView.swift", "inspector não mostra o item selecionado")
iv = open(A + "IdeaView.swift").read()
m = re.search(r"\.inspector\(isPresented: \$\w+\) \{(.*?)\.inspectorColumnWidth", iv, re.S)
if not m or "RuleListEditor(" not in m.group(1) or "promotedTopic" not in m.group(1):
    fail(A + "IdeaView.swift", "inspector da ideia sem regras rascunho / estado de promoção")
rv = open(A + "RulesView.swift").read()
if not re.search(r"\.inspector\(isPresented: \$\w+\) \{\s*ChecksList\(", rv): fail(A + "RulesView.swift", "inspector de regras sem verificações (ChecksList)")
sys.exit(bad)
PY
