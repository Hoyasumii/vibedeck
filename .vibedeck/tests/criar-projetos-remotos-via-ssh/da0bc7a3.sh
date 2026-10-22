#!/usr/bin/env bash
# DA0BC7A3: a senha informada autentica via SSH_ASKPASS, apenas no ambiente do processo filho.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $SHEET 'SecureField("Senha ou frase secreta (opcional)", text: $password)' "falta o campo de senha na conexão"
in_body $SHEET 'private func connect\(\)' 'connection\.connect\(password: secret\)' "a senha deve ser usada na conexão"
B=$(body $CONN 'func connect\(')
for p in 'environment\["SSH_ASKPASS"\] = helper\.path' 'environment\["SSH_ASKPASS_REQUIRE"\] = "force"' 'environment\["VIBEDECK_SSH_PASSWORD"\] = password' 'NumberOfPasswordPrompts=1' 'environment: environment'; do
  grep -qE -- "$p" <<<"$B" || { echo "$CONN (connect): falta '$p' na autenticação por senha"; fail=1; }
done
grep -qF 'printf '"'"'%s'"'"' \"$VIBEDECK_SSH_PASSWORD\"' <<<"$B" || { echo "$CONN: o askpass deve ler a senha da variável de ambiente"; fail=1; }
forbid $CONN 'askpass.*\\\(password\)|AtomicFile\.write\(Data\(password' "a senha não pode ser gravada no helper askpass"
finish
