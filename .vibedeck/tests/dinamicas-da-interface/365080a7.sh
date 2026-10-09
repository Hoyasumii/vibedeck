#!/usr/bin/env bash
# Boas-vindas: abre pasta (botão e ⌘O), lista recentes e, para pasta sem vibedeck.json, oferece "Inicializar projeto"
# (com nome) em vez de erro — inclusive quando a pasta chega pelo ⌘O/onOpenURL numa janela nova.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^Sources/(VibeDeckApp/(WelcomeView|VibeDeckApp)\.swift|VibeDeckCore/ProjectStore\.swift)$'; then exit 77; fi
python3 -I - <<'PY'
import re, sys
A = "Sources/VibeDeckApp/"
bad = 0
def fail(w, m):
    global bad; print(f"{w}: {m}"); bad = 1
wv = open(A + "WelcomeView.swift").read()
app = open(A + "VibeDeckApp.swift").read()
if "FolderPicker.pick()" not in wv: fail(A + "WelcomeView.swift", "boas-vindas sem \"Abrir pasta…\"")
if not re.search(r'Button\("Abrir Projeto…"\)[^\n]*\n(.*\n){0,3}\s*\.keyboardShortcut\("o"\)', app): fail(A + "VibeDeckApp.swift", "menu sem Abrir Projeto… (⌘O)")
if "recents.urls" not in wv: fail(A + "WelcomeView.swift", "boas-vindas não lista recentes")
m = re.search(r"func open\(_ url: URL\) \{(.*?)\n    \}", wv, re.S)
if not m or "ProjectStore.isProject(url)" not in m.group(1) or "pendingInit = url" not in m.group(1):
    fail(A + "WelcomeView.swift", "abrir pasta sem vibedeck.json não oferece inicializar")
if 'Button("Inicializar projeto"' not in wv or 'TextField("Nome do projeto"' not in wv: fail(A + "WelcomeView.swift", "sheet sem nome do projeto / botão Inicializar projeto")
if "ProjectStore.initialize(at: url, name:" not in wv: fail(A + "WelcomeView.swift", "Inicializar não cria o projeto (ProjectStore.initialize)")
# ⌘O e onOpenURL abrem janela com root = pasta; se não for projeto, a WelcomeView precisa oferecer inicializar para esse root.
if re.search(r"WelcomeView\(root: \$root\)", app) and not re.search(r"\.(onAppear|task)\s*\{[^}]*\broot\b[^}]*\bopen\(", wv):
    fail(A + "WelcomeView.swift", "janela aberta por ⌘O/onOpenURL com pasta sem vibedeck.json mostra só as boas-vindas: falta oferecer \"Inicializar projeto\" para o root recebido (ex.: .onAppear { if let root { open(root) } })")
sys.exit(bad)
PY
