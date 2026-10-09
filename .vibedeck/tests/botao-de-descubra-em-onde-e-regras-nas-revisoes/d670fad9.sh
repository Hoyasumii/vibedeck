#!/usr/bin/env bash
# A resposta do Claude é JSON validado; se o parse falhar, mostra um erro claro e não altera o item.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/ProjectStore\.swift$'
need "$CORE" '"--json-schema", schema' "a chamada precisa de --json-schema"
parse=$(body "$CORE" 'public static func parse\(')
printf '%s\n' "$parse" | grep -q 'throw VibeDeckError.discoverInvalidAnswer' || { echo "$CORE: parse precisa lançar discoverInvalidAnswer quando a resposta não decodifica"; fail=1; }
printf '%s\n' "$parse" | grep -qE 'try! ' && { echo "$CORE: parse usa try! (crash em vez de erro)"; fail=1; }
# Caminho Codex também valida e lança.
if grep -q 'CodexReadOnly()' "$APP"; then
  grep -A3 'JSONDecoder().decode(ReviewDiscover.Answer.self' "$APP" | grep -q 'throw VibeDeckError.discoverInvalidAnswer' || { echo "$APP: resposta do Codex que não decodifica precisa lançar discoverInvalidAnswer"; fail=1; }
fi
# Erro vira estado .failed com a mensagem; mensagem clara e dizendo que nada mudou.
need "$APP" 'state = \.failed\(error\.localizedDescription\)' "erro do Descubra precisa virar state = .failed(mensagem)"
grep -E 'case \.discoverInvalidAnswer:' Sources/VibeDeckCore/ProjectStore.swift | grep -q 'nada foi alterado' || { echo "Sources/VibeDeckCore/ProjectStore.swift: mensagem de discoverInvalidAnswer deve dizer que nada foi alterado"; fail=1; }
grep -qE 'case \.failed\(let message\):' "$VIEW" || { echo "$VIEW: o inspetor não mostra o erro do Descubra"; fail=1; }
finish
run_tests ReviewDiscoverTests/invalidOrFailedOutputThrows ReviewDiscoverTests/parsesStructuredOutput
