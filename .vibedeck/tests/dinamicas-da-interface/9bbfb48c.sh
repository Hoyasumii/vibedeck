#!/usr/bin/env bash
# Atualização ao vivo: a janela V2 liga o FileWatcher, handleExternalChanges recarrega manifesto e cada conceito,
# o eco das gravações do próprio app é ignorado (revisão do Core), editores não sobrescrevem o que o usuário digita
# e abas/seleção de itens apagados fecham.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -E '^Sources/' >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{w}: {m}"); bad = 1
def block(src, sig):
    m = re.search(sig, src)
    if not m: return ""
    i = src.index("{", m.start()); d = 0
    for j in range(i, len(src)):
        d += {"{": 1, "}": -1}.get(src[j], 0)
        if d == 0: return src[i:j + 1]
    return ""
fw = open(A + "Core/Support/FileWatcher.swift").read()
if "FSEventStreamCreate" not in fw or "kFSEventStreamCreateFlagFileEvents" not in fw:
    fail(A + "Core/Support/FileWatcher.swift", "FileWatcher não observa eventos de arquivo (FSEvents)")
pm = open(A + "ProjectModel.swift").read()
pw = open(A + "V2/V2ProjectWindow.swift").read()
sw = block(pm, r"func startWatching\(\)")
if "FileWatcher(root: store.root" not in sw or "handleExternalChanges" not in sw:
    fail(A + "ProjectModel.swift", "startWatching não observa a raiz do projeto nem chama handleExternalChanges")
if not re.search(r"\.task \{[^}]*model\.startWatching\(\)", pw): fail(A + "V2/V2ProjectWindow.swift", "janela não chama model.startWatching()")
handler = block(pm, r"func handleExternalChanges\(")
h = block(pm, r"func applyExternalChanges\(")
if not h or not handler: fail(A + "ProjectModel.swift", "handleExternalChanges/applyExternalChanges ausentes"); sys.exit(1)
if "isOwnEcho()" not in handler: fail(A + "ProjectModel.swift", "handleExternalChanges não ignora o eco do que o próprio app gravou (isOwnEcho)")
if "CoreStore.manifestName" not in h: fail(A + "ProjectModel.swift", "vibedeck.json alterado fora do app não recarrega o projeto")
enum = block(pm, r"enum SidebarSection\b")
cases = re.search(r"case ([\w, ]+)\n", enum).group(1).replace(" ", "").split(",")
for c in cases:
    if not re.search(rf"schedule\(\.{c}\)", h): fail(A + "ProjectModel.swift", f"applyExternalChanges não agenda a releitura de .{c}")
for area in ["project", "runs", "checks"]:
    if not re.search(rf"schedule\(\.{area}\)", h): fail(A + "ProjectModel.swift", f"applyExternalChanges não agenda .{area}")
# Editores de texto com autosave: mudança externa só substitui o texto se não houver edição pendente.
for f in sorted(glob.glob(A + "*.swift")):
    s = open(f).read()
    if "@State private var savedText" not in s or "scheduleSave" not in s: continue
    if not (re.search(r"if text == savedText, \w+ != text", s) or re.search(r"guard disk != savedText, disk != text", s)):
        fail(f, "editor não protege o texto digitado ao receber mudança externa (compare text com savedText)")
# Item apagado no disco: seleção e abas fecham.
if not re.search(r"\.onChange\(of: selectionExists\) \{ _, _ in pruneSelection\(\) \}", pw): fail(A + "V2/V2ProjectWindow.swift", "seleção não é podada quando o item some")
pt = block(pw, r"func pruneSelection\(\)")
if "!exists(current)" not in pt or "tabs.removeAll { !exists($0) }" not in pt: fail(A + "V2/V2ProjectWindow.swift", "pruneSelection não fecha seleção/abas de itens inexistentes")
ex = block(pm, r"func exists\(_ item: SidebarItem\)")
for c in cases:
    it = c[:-1] if c.endswith("s") else c
    if not re.search(rf"case \.{it}\(let slug\):", ex): fail(A + "ProjectModel.swift", f"exists(_:) não confere .{it} — item apagado não fecha")
sys.exit(bad)
PY
