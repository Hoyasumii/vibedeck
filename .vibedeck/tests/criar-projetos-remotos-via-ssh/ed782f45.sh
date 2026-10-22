#!/usr/bin/env bash
# ED782F45: o acesso aos arquivos remotos usa só ssh e utilitários POSIX; nenhum executável VibeDeck no servidor.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN 'try Self.capture("/usr/bin/ssh", commandArguments(inDirectory(command))' "comandos remotos devem passar pelo ssh"
for f in $CONN $WS $EXEC $READ; do
  forbid $f '"vibedeck[[:space:]]|[;&|][[:space:]]*vibedeck[[:space:]]|(command -v|which|exec)[[:space:]]+vibedeck\b' "não pode invocar um executável vibedeck no servidor"
done
hits=$(grep -rnE 'program: "vibedeck"|launcher\("vibedeck"' Sources || true)
[ -z "$hits" ] || { echo "$hits: projeto remoto não pode depender do vibedeck no servidor"; fail=1; }
in_body $WS '^public struct SSHFileTransport' 'connection\.run\(' "o transporte de arquivos deve usar a conexão SSH"
run_tests projectEditsSynchronizeAndContinueOffline
finish
