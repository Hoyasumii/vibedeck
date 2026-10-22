#!/usr/bin/env bash
# Abas na janela V2: "Abrir em Nova Aba" no menu de contexto das listas da coluna e da tabela; TabBar só com >1 aba;
# clique do meio fecha; abas e aba ativa são salvas e restauradas.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -E '^Sources/VibeDeckApp/' >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, sys
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{A}{w}: {m}"); bad = 1
def read(f): return open(A + f).read()
pw, col, tb, sl, gt = read("V2/V2ProjectWindow.swift"), read("V2/V2ContentColumn.swift"), read("TabBar.swift"), read("SectionListView.swift"), read("GroupTreeView.swift")
for name, s in [("V2/V2ContentColumn.swift", col), ("SectionListView.swift", sl), ("GroupTreeView.swift", gt)]:
    if 'LoggedButton("Abrir em Nova Aba")' not in s: fail(name, 'lista sem "Abrir em Nova Aba" no menu de contexto')
if "onOpenInNewTab(row.id)" not in col or "onOpenInNewTab(item)" not in col:
    fail("V2/V2ContentColumn.swift", "linhas e páginas devem abrir em nova aba (onOpenInNewTab)")
if "onOpenInNewTab: { openInNewTab($0) }" not in pw: fail("V2/V2ProjectWindow.swift", "janela não liga onOpenInNewTab da coluna")
if not re.search(r"if tabs\.count > 1 \{\s*TabBar\(", pw): fail("V2/V2ProjectWindow.swift", "TabBar deve aparecer só com mais de uma aba")
if not re.search(r"\.otherMouseUp", tb) or "event.buttonNumber == 2" not in tb or "onClose()" not in tb:
    fail("TabBar.swift", "clique do meio não fecha a aba")
if 'withAction(control: "tabs.select"' not in tb: fail("TabBar.swift", "troca de aba não registra ação")
for fn in ["openInNewTab", "selectTab", "closeTab", "saveTabs", "restoreTabs", "syncActiveTab"]:
    if f"func {fn}(" not in pw: fail("V2/V2ProjectWindow.swift", f"{fn} ausente")
if 'key("tabs")' not in pw or 'key("activeTab")' not in pw: fail("V2/V2ProjectWindow.swift", "abas/aba ativa não persistem (UserDefaults)")
if "restoreTabs()" not in pw.split("private func restoreState")[1]: fail("V2/V2ProjectWindow.swift", "abas não são restauradas em restoreState")
if "closeActiveTab" not in pw: fail("V2/V2ProjectWindow.swift", "⌘W não fecha a aba ativa (closeActiveTab)")
if "tabs.removeAll { !exists($0) }" not in pw: fail("V2/V2ProjectWindow.swift", "abas de itens apagados não fecham")
sys.exit(bad)
PY
