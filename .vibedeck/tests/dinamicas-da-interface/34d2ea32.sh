#!/usr/bin/env bash
# V2: a coluna da direita é o painel de IA (⇧⌘C, único .inspector da janela). O contexto do item — Revisões (tipo,
# status, prioridade, alvo, regras), Ideias (regras rascunho + promoção), Regras (verificações) e o fluxo de
# agentes/comandos/skills/workflows — fica no detalhe (.detailContext), alternado por ⌥⌘I.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -E '^Sources/VibeDeckApp/' >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{w}: {m}"); bad = 1
# Painel de IA: único inspector, atalho ⇧⌘C.
win = open(A + "V2/V2ProjectWindow.swift").read()
if not re.search(r"\.inspector\(isPresented: inspectorPresented\)", win): fail(A + "V2/V2ProjectWindow.swift", "painel de IA sem .inspector")
app = open(A + "VibeDeckApp.swift").read()
if not re.search(r'keyboardShortcut\("c", modifiers: \[\.command, \.shift\]\)', app): fail(A + "VibeDeckApp.swift", "⇧⌘C (painel de IA) ausente")
if "ClaudeChatPage()" not in win.split("private var aiPanel")[1].split("private var expandedAI")[0]: fail(A + "V2/V2ProjectWindow.swift", "o painel de IA não mostra a conversa")
for f in sorted(glob.glob(A + "*.swift") + glob.glob(A + "V2/*.swift")):
    if f.endswith("V2ProjectWindow.swift"): continue
    for n, l in enumerate(open(f).read().splitlines(), 1):
        if re.match(r"\s*\.inspector\(", l): fail(f"{f}:{n}", "inspector separado: o contexto do item vai no detalhe (.detailContext)")
# Contexto no detalhe com ⌥⌘I.
for f in ["ReviewGroupView.swift", "IdeaView.swift", "RulesView.swift", "AgentView.swift", "CommandView.swift", "SkillView.swift", "WorkflowView.swift"]:
    s = open(A + f).read()
    m = re.search(r"\.detailContext\(isPresented: \$(\w+)\)", s)
    if not m: fail(A + f, "página sem .detailContext (contexto do item no detalhe)"); continue
    v = m.group(1)
    if not re.search(rf"\{{ {v}\.toggle\(\) \}}[^\n]*\n\s*\.keyboardShortcut\(\"i\", modifiers: \[\.command, \.option\]\)", s):
        fail(A + f, f"contexto ${v} sem botão {v}.toggle() com ⌥⌘I")
rg = open(A + "ReviewGroupView.swift").read()
insp = rg[rg.find("struct ReviewItemInspector"):]
for label in ["Tipo", "Status", "Prioridade"]:
    if f'Picker("{label}"' not in insp: fail(A + "ReviewGroupView.swift", f"contexto do item sem {label}")
if "targetField(" not in insp: fail(A + "ReviewGroupView.swift", "contexto do item sem alvo (targetField)")
if "rulesSection" not in insp: fail(A + "ReviewGroupView.swift", "contexto do item sem regras ligadas")
if "ReviewItemInspector(" not in rg: fail(A + "ReviewGroupView.swift", "contexto não mostra o item selecionado")
iv = open(A + "IdeaView.swift").read()
m = re.search(r"\.detailContext\(isPresented: \$\w+\) \{(.*?)\n        \}\n", iv, re.S)
if not m or "RuleListEditor(" not in m.group(1) or "promotedTopic" not in m.group(1):
    fail(A + "IdeaView.swift", "contexto da ideia sem regras rascunho / estado de promoção")
rv = open(A + "RulesView.swift").read()
if not re.search(r"\.detailContext\(isPresented: \$\w+\) \{\s*ChecksList\(", rv): fail(A + "RulesView.swift", "contexto de regras sem verificações (ChecksList)")
dc = open(A + "V2/V2DetailContext.swift").read()
if "func detailContext" not in dc or "Divider()" not in dc: fail(A + "V2/V2DetailContext.swift", "modificador detailContext ausente")
sys.exit(bad)
PY
