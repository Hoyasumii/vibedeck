#!/usr/bin/env bash
# AF0519D5: projeto SSH recente reabre offline com dados e pendências do cache e indica "Desconectado".
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $APPF '.onAppear { RecentProjects.shared.add(root) }' "projetos abertos devem entrar nos recentes"
needF $WELCOME 'RemoteWorkspace.existing(at: url)?.destination.title' "recentes devem identificar o destino SSH"
in_body $WS 'public static func existing' 'VDJSON\.decoder\.decode\(State\.self' "o estado do projeto SSH deve ser recuperado do disco sem conexão"
need $WINDOW 'RemoteWorkspace\.existing\(at: model\.store\.root\).*RemoteProjectBar' "o projeto reaberto deve mostrar o estado da conexão"
needF $SHEET 'var message = "Desconectado"' "o estado inicial deve ser desconectado"
in_body $SHEET 'func synchronize\(force' 'message = "Desconectado · \\\(workspace\.pendingCount\) pendência' "falha de conexão deve indicar desconectado e pendências"
run_tests durableEditsDeletionAndRestart failedUploadRetainsDurablePendingAndBase
finish
