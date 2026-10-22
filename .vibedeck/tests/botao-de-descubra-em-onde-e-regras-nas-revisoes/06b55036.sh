#!/usr/bin/env bash
set -euo pipefail
# Arquivos sugeridos precisam existir no projeto e slugs sugeridos precisam ser tópicos existentes;
# o resto é descartado antes de mostrar a proposta.
source "$(dirname "$0")/_lib.sh"
applies
prop=$(body "$CORE" 'static func proposal\(')
printf '%s\n' "$prop" | grep 'existingFile(' >/dev/null || { echo "$CORE: proposal não valida arquivos com existingFile"; fail=1; }
printf '%s\n' "$prop" | grep 'candidateTopics(' >/dev/null || { echo "$CORE: proposal não restringe tópicos a candidateTopics"; fail=1; }
ex=$(body "$CORE" 'static func existingFile\(')
printf '%s\n' "$ex" | grep 'fileExists(' >/dev/null || { echo "$CORE: existingFile não confere se o arquivo existe"; fail=1; }
printf '%s\n' "$ex" | grep 'hasPrefix(rootPath)' >/dev/null || { echo "$CORE: existingFile não confere se o arquivo está dentro do projeto"; fail=1; }
# As duas origens (Claude e Codex) passam pela mesma validação antes do .ready.
n=$(grep -c 'state = \.ready(' "$APP" || true)
m=$(grep -c 'state = \.ready(ReviewDiscover\.proposal(' "$APP" || true)
[ "$n" -ge 1 ] && [ "$n" -eq "$m" ] || { echo "$APP: todo state = .ready(…) precisa passar por ReviewDiscover.proposal"; fail=1; }
# Gêmeo no Core Rust.
rp=$(body "$RS" '^pub fn proposal\(')
printf '%s\n' "$rp" | grep 'existing_file(' >/dev/null || { echo "$RS: proposal não valida arquivos com existing_file"; fail=1; }
printf '%s\n' "$rp" | grep 'candidate_topics(' >/dev/null || { echo "$RS: proposal não restringe tópicos a candidate_topics"; fail=1; }
re=$(body "$RS" '^pub fn existing_file\(')
printf '%s\n' "$re" | grep 'is_file()' >/dev/null || { echo "$RS: existing_file não confere se é arquivo existente"; fail=1; }
printf '%s\n' "$re" | grep 'strip_prefix(&root_norm)' >/dev/null || { echo "$RS: existing_file não confere se o arquivo está dentro do projeto"; fail=1; }
rtest proposta_descarta_inexistentes
finish
