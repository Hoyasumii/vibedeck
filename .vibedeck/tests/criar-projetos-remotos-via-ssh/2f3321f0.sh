#!/usr/bin/env bash
# 2F3321F0: o projeto SSH orienta autenticar o provedor no servidor e oferece abrir o Terminal SSH.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $SHEET '^struct RemoteProjectBar')
grep -qF 'LoggedButton("Terminal SSH") { session.openTerminal() }' <<<"$B" || { echo "$SHEET: falta a ação 'Terminal SSH' no projeto remoto"; fail=1; }
grep -qF 'Para autenticar a IA, abra o Terminal SSH e execute claude ou codex no servidor.' <<<"$B" || { echo "$SHEET: falta a orientação de autenticação do provedor no servidor"; fail=1; }
needF $TERM 'executable: "/usr/bin/ssh"' "o terminal oferecido deve abrir no servidor"
finish
