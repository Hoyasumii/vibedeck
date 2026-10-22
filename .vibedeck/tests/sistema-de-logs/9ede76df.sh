#!/usr/bin/env bash
# Toda ação do usuário no app grava info/app: controles SwiftUI passam por Logged*/.logging, menus nativos pelo hook.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies "$LOG_SCOPE"
fail=0
bad() { echo "$1"; fail=1; }
L=$APPLOG
region "$L" 'static func withAction' '^    }$' | grep  'info("ui.activated"' >/dev/null || bad "$L: withAction deve gravar info 'ui.activated'"
region "$L" 'static func withAction' '^    }$' | grep  'component: .app' >/dev/null || bad "$L: withAction deve usar component .app"
# Botões: nenhum Button/Menu cru fora de LoggedControls.swift.
# Exceção: Button cujo corpo chama docGenerator.start, que abre a ação docs.generate (DocGenerate.swift).
while IFS=: read -r f n _; do
  sed -n "${n},$((n+3))p" "$f" | grep  'docGenerator.start(' >/dev/null && continue
  bad "$f:$n: Button sem LoggedButton"
done < <(grep -rnE '(^|[^A-Za-z.])Button[ ({]' Sources/VibeDeckApp --include='*.swift' | grep -v 'LoggedControls.swift' | grep -vE '^\S+:[0-9]+:\s*//' || true)
# Pickers e Toggles: o binding precisa passar por .logging(...) (olha a declaração e as 4 linhas seguintes).
for f in Sources/VibeDeckApp/*.swift; do
  awk -v f="$f" '/(^|[^A-Za-z.])(Picker|Toggle)\(/ && !/Logged/ {start=NR; found=0; hit=$0}
       start && /\.logging\(|LoggedSelection|\$[a-zA-Z]+\)?\.logging/ {found=1}
       start && NR-start==4 {if(!found) printf "%s:%d: Picker/Toggle sem .logging(control:label:)\n", f, start; start=0}' "$f"
done > /tmp/vd_9ede_$$.txt
if [ -s /tmp/vd_9ede_$$.txt ]; then cat /tmp/vd_9ede_$$.txt; fail=1; fi
rm -f /tmp/vd_9ede_$$.txt
# Menus/atalhos nativos e abas.
grep -q 'NativeActionLogging.install()' Sources/VibeDeckApp/VibeDeckApp.swift || bad "VibeDeckApp.swift: NativeActionLogging.install() não é chamado"
grep -q 'withAction(control: "tabs.select"' Sources/VibeDeckApp/TabBar.swift || bad "TabBar.swift: troca de aba não registra ação"
[ $fail -eq 0 ] || exit 1
