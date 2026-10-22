#!/usr/bin/env bash
set -euo pipefail
# A resposta do Claude é JSON validado; se o parse falhar, mostra um erro claro e não altera o item.
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/Core/Model/VibeDeckError\.swift$|^Sources/VibeDeckApp/Core/AI/CodexReadOnly\.swift$'
need "$CORE" '"--json-schema", schema' "a chamada precisa de --json-schema"
need "$RS" '"--json-schema"' "a chamada do Core Rust precisa de --json-schema"
parse=$(body "$CORE" 'static func parse\(')
printf '%s\n' "$parse" | grep 'throw VibeDeckError.discoverInvalidAnswer' >/dev/null || { echo "$CORE: parse precisa lançar discoverInvalidAnswer quando a resposta não decodifica"; fail=1; }
printf '%s\n' "$parse" | grep -E 'try! ' >/dev/null && { echo "$CORE: parse usa try! (crash em vez de erro)"; fail=1; }
rparse=$(body "$RS" '^pub fn parse\(')
printf '%s\n' "$rparse" | grep 'DiscoverError::InvalidAnswer' >/dev/null || { echo "$RS: parse precisa devolver InvalidAnswer quando a resposta não decodifica"; fail=1; }
printf '%s\n' "$rparse" | grep -E 'unwrap\(\)|expect\(' >/dev/null && { echo "$RS: parse usa unwrap/expect (panic em vez de erro)"; fail=1; }
# A validação do app (todos os caminhos: Claude e Codex) acontece no parse da operação compartilhada.
grep -q 'guard value\["fields"\]?.array != nil, value\["rules"\]?.array != nil else { throw VibeDeckError.discoverInvalidAnswer }' "$APP" || { echo "$APP: a resposta precisa ser validada (fields e rules) antes de virar proposta"; fail=1; }
grep -q 'JSONDecoder().decode(ReviewDiscover.Answer.self' "$APP" || { echo "$APP: a resposta precisa ser decodificada como ReviewDiscover.Answer"; fail=1; }
# Erro vira estado .failed com a mensagem; mensagem clara e dizendo que nada mudou.
need "$APP" 'state = \.failed\(error\.localizedDescription\)' "erro do Descubra precisa virar state = .failed(mensagem)"
grep -E 'case \.discoverInvalidAnswer:' Sources/VibeDeckApp/Core/Model/VibeDeckError.swift | grep 'nada foi alterado' >/dev/null || { echo "Sources/VibeDeckApp/Core/Model/VibeDeckError.swift: mensagem de discoverInvalidAnswer deve dizer que nada foi alterado"; fail=1; }
grep -qE 'case \.failed\(let message\):' "$VIEW" || { echo "$VIEW: o inspetor não mostra o erro do Descubra"; fail=1; }
rtest saida_invalida_ou_falha saida_estruturada
finish
