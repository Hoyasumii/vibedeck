#!/usr/bin/env bash
# B24AE286: após conectar, navega por subpastas e pasta pai do servidor e seleciona uma pasta.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
in_body $CONN 'func directories\(\)' 'find \. -mindepth 1 -maxdepth 1 -type d' "a listagem deve trazer as subpastas do diretório atual"
in_body $CONN 'func resolved\(directory' 'pwd -P' "o diretório navegado deve ser resolvido no servidor"
in_body $SHEET 'private func navigate' 'SSHConnection\(resolved\)\.directories\(\)' "navegar deve listar as subpastas do destino"
needF $SHEET 'List(directories, id: \.self)' "faltam as subpastas na interface"
needF $SHEET 'appendingPathComponent(directory)' "clicar numa subpasta deve entrar nela"
needF $SHEET 'LoggedButton("Pasta pai") { navigate(((destination?.directory ?? path) as NSString).deletingLastPathComponent)' "falta a ação de voltar à pasta pai"
needF $SHEET 'LoggedButton("Abrir esta pasta") { openSelected() }' "falta a seleção da pasta remota atual"
in_body $SHEET 'private func connect\(\)' 'navigate\(home\)' "após conectar a navegação deve começar"
finish
