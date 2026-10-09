#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Features de IA só aparecem com um provedor instalado; a detecção é única (AIProvider).
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
GATE = re.compile(r"AIProvider\.installed|\.isInstalled|AIProvider\.\w+\.isInstalled")
# 1. Localizar executáveis de IA só em ClaudeCode/AIProvider.
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    if f in ("Sources/VibeDeckCore/ClaudeCode.swift", "Sources/VibeDeckCore/AIProvider.swift"): continue
    for i, l in enumerate(open(f).read().split("\n")):
        if re.search(r"command -v (claude|codex)|\bwhich (claude|codex)", l):
            fail(f"{f}:{i+1}: detecção própria de provedor (use AIProvider): {l.strip()}")
# 2. Na UI do app.
ENTRY = re.compile(r"\b(testsMenu|generateMenu|discoverButton|AIUsageView\(\)|ClaudeUsageView\(\)|AIProviderSettingsView\(|ClaudeChatPage\(\)|CloudLaunchSheet\(|import(Agents|Commands|Skills)\()")
for f in sorted(glob.glob("Sources/VibeDeckApp/*.swift")):
    lines = open(f).read().split("\n")
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith("//"): continue
        if re.search(r"\b(ClaudeCode|CodexCode)\.isInstalled\b", l):
            fail(f"{f}:{i+1}: detecção fora de AIProvider (use AIProvider.<p>.isInstalled / AIProvider.installed): {s}")
        if re.search(r"\.disabled\([^)]*isInstalled", l):
            fail(f"{f}:{i+1}: opção de provedor não instalado aparece desabilitada (deveria ficar oculta): {s}")
        if re.search(r"ForEach\(AIProvider\.allCases", l):
            body = "\n".join(lines[i:i+4])
            if not re.search(r"isInstalled|AIProvider\.installed", body):
                fail(f"{f}:{i+1}: lista todos os provedores sem filtrar os instalados (use AIProvider.installed): {s}")
        m = ENTRY.search(l)
        if m and not re.search(r"(private |)(var|func|struct) ", l):
            ctx = "\n".join(lines[max(0, i-6):i+1])
            # ClaudeChatPage só é alcançável pelo item "IA" da barra lateral, que é condicionado.
            if m.group(1) == "ClaudeChatPage()" or m.group(1).startswith("CloudLaunchSheet"): continue
            if not GATE.search(ctx):
                fail(f"{f}:{i+1}: funcionalidade de IA ({m.group(1).rstrip('(')}) exibida sem checar provedor instalado")
# 3. Pontos de entrada da página de IA condicionados.
pw = open("Sources/VibeDeckApp/ProjectWindow.swift").read().split("\n")
for i, l in enumerate(pw):
    if re.search(r'\.tag\(SidebarItem\.claude\)', l) and not GATE.search("\n".join(pw[max(0, i-4):i])):
        fail(f"Sources/VibeDeckApp/ProjectWindow.swift:{i+1}: item IA da barra lateral sem checar provedor")
app = open("Sources/VibeDeckApp/VibeDeckApp.swift").read().split("\n")
for i, l in enumerate(app):
    if 'Button("Abrir IA")' in l and not GATE.search("\n".join(app[max(0, i-3):i])):
        fail(f"Sources/VibeDeckApp/VibeDeckApp.swift:{i+1}: menu Abrir IA sem checar provedor")
# 4. AIProvider cobre exatamente Claude e Codex.
ap = open("Sources/VibeDeckCore/AIProvider.swift").read()
if not re.search(r"enum AIProvider\b[^{]*\{\s*case claude, codex\s*\n", ap):
    fail("Sources/VibeDeckCore/AIProvider.swift: AIProvider deve ter só os casos claude e codex")
if "static var installed" not in ap or "var isInstalled" not in ap:
    fail("Sources/VibeDeckCore/AIProvider.swift: falta AIProvider.installed / isInstalled")
sys.exit(bad)
PY
