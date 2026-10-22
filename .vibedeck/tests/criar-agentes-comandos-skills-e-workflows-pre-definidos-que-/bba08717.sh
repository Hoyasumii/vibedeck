#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# BBA08717 (should): conteúdos pré-definidos instruem seguir padrões do projeto (regras, revisão, check) e evitar código espaguete, sem citar caminhos do VibeDeck.
for f in "$ASSETS"/*.json "$ASSETS"/guidance.txt "$ASSETS"/policy.txt; do
  forbid "$f" 'Sources/VibeDeck|VibeDeckCore|VibeDeckApp|\.swift|ProjectStore|ProjectModel|crates/' "texto do catálogo não deve citar caminhos/nomes internos do VibeDeck"
done
need "$ASSETS/guidance.txt" 'código espaguete' "conteúdo deve instruir evitar código espaguete"
need "$ASSETS/guidance.txt" 'regras' "conteúdo deve citar regras do projeto"
need "$ASSETS/guidance.txt" 'submit_rule_check' "conteúdo deve citar o fluxo de check"
need "$ASSETS/guidance.txt" 'revisão' "conteúdo deve citar o fluxo de revisão"
need "$KITS" 'include_str!\("\.\./\.\./assets/kits/guidance\.txt"\)' "a orientação comum deve ser anexada a todos os prompts"
finish
