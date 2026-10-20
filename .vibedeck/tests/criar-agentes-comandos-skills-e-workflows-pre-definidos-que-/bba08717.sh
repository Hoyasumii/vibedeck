#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
forbid "$CAT" 'Sources/VibeDeck|VibeDeckCore|VibeDeckApp|\.swift|ProjectStore|ProjectModel' "texto do catálogo não deve citar caminhos/nomes do VibeDeck"
forbid Sources/VibeDeckCore/AIPromptPolicy.swift 'Sources/VibeDeck|\.swift' "política de prompt não deve citar caminhos"
need "$CAT" 'código espaguete' "conteúdo deve instruir evitar código espaguete"
need "$CAT" 'regras' "conteúdo deve citar regras do projeto"
need "$CAT" 'submit_rule_check' "conteúdo deve citar fluxo de check"
need "$CAT" 'item *\n?.*de revisão|revisão' "conteúdo deve citar fluxo de revisão"
finish
