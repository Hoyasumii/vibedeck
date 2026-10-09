#!/usr/bin/env bash
# Arquivos sugeridos precisam existir no projeto e slugs sugeridos precisam ser tópicos existentes;
# o resto é descartado antes de mostrar a proposta.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
prop=$(body "$CORE" 'public static func proposal\(')
printf '%s\n' "$prop" | grep -q 'existingFile(' || { echo "$CORE: proposal não valida arquivos com existingFile"; fail=1; }
printf '%s\n' "$prop" | grep -q 'candidateTopics(' || { echo "$CORE: proposal não restringe tópicos a candidateTopics"; fail=1; }
ex=$(body "$CORE" 'static func existingFile\(')
printf '%s\n' "$ex" | grep -q 'fileExists(' || { echo "$CORE: existingFile não confere se o arquivo existe"; fail=1; }
printf '%s\n' "$ex" | grep -q 'hasPrefix(rootPath)' || { echo "$CORE: existingFile não confere se o arquivo está dentro do projeto"; fail=1; }
# As duas origens (Claude e Codex) passam pela mesma validação antes do .ready.
n=$(grep -c 'state = \.ready(' "$APP" || true)
m=$(grep -c 'state = \.ready(ReviewDiscover\.proposal(' "$APP" || true)
[ "$n" -ge 1 ] && [ "$n" -eq "$m" ] || { echo "$APP: todo state = .ready(…) precisa passar por ReviewDiscover.proposal"; fail=1; }
finish
run_tests ReviewDiscoverTests/proposalDropsMissingFilesAndUnknownTopics ReviewDiscoverTests/replacingNeedsOptInAndTopicsOnlyAdd
