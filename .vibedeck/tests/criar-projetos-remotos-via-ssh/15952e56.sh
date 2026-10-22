#!/usr/bin/env bash
# 15952E56: a configuração SSH tem servidor, porta e usuário, e esses valores chegam ao ssh (-p/-l).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
for f in Servidor Porta Usuário; do needF $SHEET "LoggedTextField(\"$f\"" "falta o campo '$f' na configuração SSH"; done
in_body $SHEET 'private func connect\(\)' 'guard let port = Int\(port\)' "a porta informada deve ser lida"
in_body $SHEET 'private func connect\(\)' 'SSHDestination\(host: host, port: port, user: user\)' "o destino manual deve usar servidor, porta e usuário informados"
needF $CONN '"-p", String(destination.port)' "o ssh deve receber a porta do destino"
needF $CONN '"-l", destination.user' "o ssh deve receber o usuário do destino"
finish
