#!/usr/bin/env bash
# 1F73B1D5: a senha só é guardada com opção explícita (desmarcada por padrão) e só no Chaves do macOS.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $SHEET '@State private var remember = false' "a opção de guardar senha deve iniciar desmarcada"
needF $SHEET 'var remember = false' "a opção de guardar senha na reconexão deve iniciar desmarcada"
needF $SHEET 'Toggle("Guardar senha no Chaves do macOS"' "falta a opção explícita de guardar a senha"
B=$(body $CONN '^public enum SSHCredentials')
for p in 'kSecClassGenericPassword' 'SecItemAdd' 'SecItemCopyMatching' 'SecItemDelete'; do grep -q "$p" <<<"$B" || { echo "$CONN: SSHCredentials deve usar $p (Chaves do macOS)"; fail=1; }; done
# Toda gravação de senha depende da opção explícita.
while IFS= read -r hit; do
  grep -q 'remember' <<<"$hit" || { echo "${hit%%:*}:$(cut -d: -f2 <<<"$hit"): SSHCredentials.store sem depender da opção 'remember'"; fail=1; }
done < <(grep -rn 'SSHCredentials\.store' Sources)
for f in $SHEET $CONN $WS; do forbid $f 'UserDefaults|@AppStorage' "credenciais SSH não podem ir para preferências"; done
forbid $CONN 'AtomicFile\.write\(.*password' "a senha não pode ser gravada em arquivo"
finish
