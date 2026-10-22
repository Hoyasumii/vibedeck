#!/usr/bin/env bash
# README e .vibedeck/guide.md descrevem (pt-BR) o visualizador interno do painel Links e o Fechar.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'README\.md|\.vibedeck/guide\.md|Sources/VibeDeckApp/LinksView\.swift'

for doc in README.md .vibedeck/guide.md; do
  [ -f "$doc" ] || { bad "$doc: não encontrado"; continue; }
  txt=$(tr '\n' ' ' < "$doc")
  grep -q 'No painel \*\*Links\*\*' <<<"$txt" || bad "$doc: falta descrever o painel **Links**"
  grep -Eq 'Abrir\*\*|duplo clique' <<<"$txt" || bad "$doc: falta dizer como abrir o link (duplo clique/Abrir)"
  grep -q 'visualizador interno' <<<"$txt" || bad "$doc: falta mencionar o visualizador interno"
  grep -q '\*\*Fechar\*\* esconde o painel' <<<"$txt" || bad "$doc: falta dizer que **Fechar** esconde o painel"
done
exit $fail
