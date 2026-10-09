#!/usr/bin/env bash
# Abas: "Abrir em Nova Aba" em toda linha da sidebar e nas listas; TabBar só com >1 aba; clique do meio fecha;
# abas salvas e restauradas.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/VibeDeckApp/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{w}: {m}"); bad = 1
pw = open(A + "ProjectWindow.swift").read()
lines = pw.splitlines()
# Toda linha com .tag(SidebarItem.x) (exceto o Terminal, que é ação) tem menu com openInNewTabButton do mesmo item.
for n, l in enumerate(lines, 1):
    m = re.search(r"\.tag\(SidebarItem\.(\w+)(\(([^)]*)\))?\)", l)
    if not m: continue
    window = "\n".join(lines[n - 1:n + 3])
    want = f"openInNewTabButton(.{m.group(1)}"
    if ".contextMenu" not in window or want not in "\n".join(lines[n - 1:n + 4]):
        fail(f"{A}ProjectWindow.swift:{n}", f"linha .{m.group(1)} da sidebar sem \"Abrir em Nova Aba\" no menu de contexto")
if 'Button("Abrir em Nova Aba") { openInNewTab(item) }' not in pw: fail(A + "ProjectWindow.swift", "openInNewTabButton não abre em nova aba")
for f in ["SectionListView.swift", "PatternsView.swift"]:
    s = open(A + f).read()
    if "onOpenInNewTab" in s or f == "SectionListView.swift":
        if 'Button("Abrir em Nova Aba")' not in s: fail(A + f, "lista sem \"Abrir em Nova Aba\" no menu de contexto")
if not re.search(r"if tabs\.count > 1 \{\s*TabBar\(", pw): fail(A + "ProjectWindow.swift", "TabBar deve aparecer só com mais de uma aba")
tb = open(A + "TabBar.swift").read()
if not re.search(r"\.otherMouseUp", tb) or "event.buttonNumber == 2" not in tb or "onClose()" not in tb:
    fail(A + "TabBar.swift", "clique do meio não fecha a aba")
if not re.search(r"\.onChange\(of: tabs\)[^\n]*\n(.*\n){0,4}.*UserDefaults\.standard\.set\([^\n]*forKey: tabsKey\)", pw):
    fail(A + "ProjectWindow.swift", "abas não são gravadas (UserDefaults, tabsKey)")
if not re.search(r"defaults\.stringArray\(forKey: tabsKey\)", pw): fail(A + "ProjectWindow.swift", "abas não são restauradas ao abrir")
if "activeTabKey" not in pw: fail(A + "ProjectWindow.swift", "aba ativa não persiste")
sys.exit(bad)
PY
