#!/usr/bin/env bash
# 9AE36B34: pasta sem vibedeck.json pede confirmação; nada é criado antes de "Inicializar projeto".
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $SHEET 'private func openSelected')
ln() { grep -nF -- "$1" <<<"$B" | head -1 | cut -d: -f1; }
ask=$(ln 'name = (path as NSString).lastPathComponent; initialize = true; return')
create=$(ln 'try ProjectStore.initialize(at: workspace.root, name: name)')
sync=$(ln 'try workspace.synchronize(using: transport)')
guard=$(ln 'guard snapshot["vibedeck.json"] == nil else')
if [ -z "$ask" ] || [ -z "$create" ] || [ -z "$sync" ] || [ -z "$guard" ]; then
  echo "$SHEET (openSelected): fluxo de inicialização incompleto (pergunta=$ask, guard=$guard, criação=$create, envio=$sync)"; fail=1
elif [ "$ask" -ge "$create" ] || [ "$ask" -ge "$sync" ] || [ "$guard" -ge "$create" ]; then
  echo "$SHEET (openSelected): a confirmação deve ocorrer antes de criar ou enviar arquivos"; fail=1
fi
grep -qF 'if create {' <<<"$B" || { echo "$SHEET: a criação deve depender da confirmação (create)"; fail=1; }
needF $SHEET 'LoggedButton("Cancelar", role: .cancel) { initialize = false }' "cancelar a inicialização não pode criar arquivos"
needF $SHEET 'LoggedButton("Inicializar projeto") { initialize = false; openSelected(create: true) }' "falta a confirmação explícita"
needF $SHEET 'Criar vibedeck.json e .vibedeck/ em' "a confirmação deve indicar o que será criado"
run_tests projectEditsSynchronizeAndContinueOffline
finish
