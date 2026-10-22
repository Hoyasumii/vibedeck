#!/usr/bin/env bash
# E6158DCD: sem conexão, as edições continuam no cache local e ficam pendentes.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckCore/ProjectStore\.swift$'
forbid Sources/VibeDeckCore/ProjectStore.swift 'SSHConnection|requireSynchronized|SSHFileTransport' "a edição local não pode depender da conexão SSH"
not_in_body $SHEET '^struct RemoteProjectBar' 'dismiss\(\)|root = nil' "perder a conexão não pode fechar o projeto"
in_body $SHEET 'func synchronize\(force' 'message = "Desconectado' "a falha de conexão deve manter o projeto aberto como desconectado"
run_tests projectEditsSynchronizeAndContinueOffline durableEditsDeletionAndRestart
finish
