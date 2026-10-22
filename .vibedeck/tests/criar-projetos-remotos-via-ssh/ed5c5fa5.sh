#!/usr/bin/env bash
# ED5C5FA5: a tela inicial oferece "Conectar via SSH…", que abre a configuração SSH sem escolher pasta local.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $WELCOME 'LoggedButton("Conectar via SSH…") { sshSheet = true }' "falta a ação 'Conectar via SSH…' na tela inicial"
need $WELCOME '\.sheet\(isPresented: \$sshSheet\) \{ SSHProjectSheet' "a ação SSH deve apresentar SSHProjectSheet"
forbid $WELCOME 'Conectar via SSH.*(FolderPicker|NSOpenPanel)' "a ação SSH não pode pedir uma pasta local"
need $APPF 'WelcomeView\(root: \$root\)' "a tela inicial (WelcomeView) deve aparecer sem projeto aberto"
not_in_body $SHEET '^struct SSHProjectSheet' 'FolderPicker|NSOpenPanel' "o fluxo SSH não pode exigir pasta local"
in_body $SHEET '^struct SSHProjectSheet' 'onOpen\(workspace\.root\)' "o fluxo SSH deve abrir o projeto conectado"
finish
