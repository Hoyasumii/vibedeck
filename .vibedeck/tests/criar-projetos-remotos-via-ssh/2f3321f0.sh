#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 2F3321F0: o projeto SSH orienta autenticar o provedor no servidor e oferece abrir o Terminal SSH.
needF $STATUS 'LoggedButton("Terminal SSH") { claude.openTerminal() }' "falta a ação 'Terminal SSH' no projeto remoto"
needF $STATUS 'Para autenticar a IA, abra o Terminal SSH e execute claude ou codex no servidor.' "falta a orientação de autenticação do provedor no servidor"
needF $TERM 'executable: "/usr/bin/ssh"' "o terminal oferecido deve abrir no servidor"
needF $STATUSBAR 'V2RemoteEnvironmentSegment(link: link)' "o estado/ações do projeto SSH devem aparecer na barra de status"
finish
