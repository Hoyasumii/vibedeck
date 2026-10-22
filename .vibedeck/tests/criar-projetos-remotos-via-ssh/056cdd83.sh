#!/usr/bin/env bash
# 056CDD83: provedor ausente no servidor é informado; nada é instalado, trocado ou executado localmente.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $EXEC 'Instale no servidor ou selecione outro provedor manualmente.' "a ausência do provedor deve ser informada ao usuário"
needF $EXEC '>&2; exit 127; }; exec ' "a ação deve parar quando o provedor falta"
forbid $EXEC '(npm|brew|pip3?|bun|apt(-get)?|yum|dnf) +(install|add|i) |curl [^"]*\| *(ba)?sh' "não pode instalar o provedor automaticamente"
B=$(body $EXEC 'static func configure')
grep -qE 'AIProvider\.|provider =' <<<"$B" && { echo "$EXEC (configure): não pode trocar de provedor automaticamente"; fail=1; }
finish
