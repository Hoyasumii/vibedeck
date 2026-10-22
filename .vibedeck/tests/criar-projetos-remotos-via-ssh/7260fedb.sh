#!/usr/bin/env bash
# 7260FEDB: sem senha, a conexão usa as chaves/agente do OpenSSH em modo não interativo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN '"/usr/bin/ssh"' "a conexão deve usar o OpenSSH do sistema"
in_body $CONN 'func connect\(' 'else \{ args \+= \["-o", "BatchMode=yes"\] \}' "sem senha a conexão deve usar BatchMode (chave/agente, sem pedir senha)"
forbid $CONN 'PubkeyAuthentication=no|PreferredAuthentications=(password|keyboard)|IdentityAgent=none' "a autenticação por chave não pode ser desativada"
needF $SHEET 'Sem senha, usa as chaves e o agente SSH' "a interface deve indicar o uso de chave quando a senha fica vazia"
in_body $SHEET 'private func connect\(\)' 'password\.isEmpty \? SSHCredentials\.password' "senha vazia não pode ser obrigatória"
finish
