#!/usr/bin/env bash
# 3B2802CA: servidor desconhecido exige confirmar a impressão digital; chave alterada bloqueia a conexão.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN '"StrictHostKeyChecking=yes"' "o ssh deve recusar chaves não confirmadas"
for f in $(grep -rlE 'StrictHostKeyChecking|UserKnownHostsFile' Sources); do
  forbid $f 'StrictHostKeyChecking=(no|accept-new|off)|UserKnownHostsFile=/dev/null' "não pode aceitar chaves sem confirmação"
done
in_body $CONN 'public func unknownHostKeys' 'ssh-keygen", \["-F"' "deve verificar se o servidor já é conhecido"
in_body $CONN 'public func unknownHostKeys' 'ssh-keyscan' "deve obter a chave do servidor desconhecido"
in_body $CONN 'public static func fingerprints' 'ssh-keygen", \["-lf", "-"\]' "deve calcular a impressão digital"
in_body $CONN 'public func connect\(' 'REMOTE HOST IDENTIFICATION HAS CHANGED' "chave alterada deve ser detectada"
needF $CONN 'A chave conhecida do servidor mudou. Conexão bloqueada: confirme a identidade' "chave alterada deve bloquear e orientar"
in_body $SHEET 'private func connect\(\)' 'fingerprints = try SSHConnection\.fingerprints\(candidate\); keys = candidate; return' "servidor desconhecido deve parar e pedir confirmação"
needF $SHEET 'confirmationDialog("Confiar neste servidor SSH?"' "falta a confirmação explícita"
needF $SHEET 'Text(fingerprints + "\nConfirme a impressão digital' "a impressão digital deve ser apresentada"
c=$(grep -c 'SSHConnection\.trust(' $SHEET || true)
[ "$c" = 1 ] && grep -qF 'LoggedButton("Confiar e conectar")' $SHEET || { echo "$SHEET: a chave só pode ser confiada pelo botão 'Confiar e conectar'"; fail=1; }
run_tests connectionArgumentsUsePortUserAliasAndStrictHostKeys
finish
