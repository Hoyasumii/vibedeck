#!/usr/bin/env bash
# 4D6A689A: aliases do ~/.ssh/config (com Include) são oferecidos e o alias é o alvo do ssh (preserva IdentityFile, ProxyJump...).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $SHEET 'ForEach(SSHConnection.aliases()' "o seletor deve listar os aliases da configuração SSH local"
need $SHEET 'SSHConnection\.configuration\(alias:' "o alias selecionado deve ser resolvido pela configuração SSH"
in_body $SHEET 'private func connect\(\)' 'SSHDestination\(host: resolved\.host, port: port, user: user, alias: alias\)' "a conexão por alias deve manter o alias no destino"
needF $CONN '["-G", "--", alias]' "a configuração do alias deve vir de 'ssh -G'"
in_body $CONN 'func commandArguments' 'destination\.alias \?\? destination\.host' "o alvo do ssh deve ser o alias quando houver"
in_body $CONN 'func connect\(' 'destination\.alias \?\? destination\.host' "a conexão deve usar o alias quando houver"
finish
