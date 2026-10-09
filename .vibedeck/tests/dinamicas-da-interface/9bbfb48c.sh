#!/usr/bin/env bash
# Atualização ao vivo: a janela liga o FileWatcher, handleExternalChanges recarrega manifesto e cada conceito,
# editores de texto não sobrescrevem o que o usuário digita, e abas de itens apagados fecham.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/'; then exit 77; fi
python3 -I - <<'PY'
import re, sys
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
fw = open("Sources/VibeDeckCore/FileWatcher.swift").read()
if "FSEventStreamCreate" not in fw or "kFSEventStreamCreateFlagFileEvents" not in fw:
    fail("Sources/VibeDeckCore/FileWatcher.swift", "FileWatcher não observa eventos de arquivo (FSEvents)")
pm = open(A + "ProjectModel.swift").read()
pw = open(A + "ProjectWindow.swift").read()
sw = block(pm, r"func startWatching\(\)")
if "FileWatcher(root: store.root" not in sw or "handleExternalChanges" not in sw:
    fail(A + "ProjectModel.swift", "startWatching não observa a raiz do projeto nem chama handleExternalChanges")
if not re.search(r"\.task \{[^}]*model\.startWatching\(\)", pw): fail(A + "ProjectWindow.swift", "janela não chama model.startWatching()")
h = block(pm, r"func handleExternalChanges\(")
if not h: fail(A + "ProjectModel.swift", "handleExternalChanges ausente"); sys.exit(1)
if "lastWritten" not in h: fail(A + "ProjectModel.swift", "handleExternalChanges não ignora o que o próprio app gravou (lastWritten)")
if "ProjectStore.manifestName" not in h or "loadProject()" not in h: fail(A + "ProjectModel.swift", "vibedeck.json alterado fora do app não recarrega o projeto")
enum = block(pm, r"enum SidebarSection\b")
cases = re.search(r"case ([\w, ]+)\n", enum).group(1).replace(" ", "").split(",")
for c in cases:
    fn = "reload" + c[0].upper() + c[1:]
    if not re.search(rf"\b{fn}\(\)", h): fail(A + "ProjectModel.swift", f"handleExternalChanges não chama {fn}() — seção .{c} não atualiza ao vivo")
    elif not re.search(rf"func {fn}\(\)", pm): fail(A + "ProjectModel.swift", f"{fn}() não definido")
# Editores de texto com autosave: mudança externa só substitui o texto se não houver edição pendente.
import glob
for f in sorted(glob.glob(A + "*.swift")):
    s = open(f).read()
    if "@State private var savedText" not in s or "scheduleSave" not in s: continue
    if not (re.search(r"if text == savedText, \w+ != text", s) or re.search(r"guard disk != savedText, disk != text", s)):
        fail(f, "editor não protege o texto digitado ao receber mudança externa (compare text com savedText)")
# Item apagado no disco: abas fecham.
if not re.search(r"\.onChange\(of: tabs\.map\(exists\)\) \{ pruneTabs\(\) \}", pw): fail(A + "ProjectWindow.swift", "abas não são podadas quando o item some")
pt = block(pw, r"func pruneTabs\(\)")
if "tabs.filter(exists)" not in pt: fail(A + "ProjectWindow.swift", "pruneTabs não remove abas de itens inexistentes")
ex = block(pm, r"func exists\(_ item: SidebarItem\)")
for c in cases:
    it = c[:-1] if c.endswith("s") else c
    if not re.search(rf"case \.{it}\(let slug\):", ex): fail(A + "ProjectModel.swift", f"exists(_:) não confere .{it} — aba de item apagado não fecha")
sys.exit(bad)
PY
