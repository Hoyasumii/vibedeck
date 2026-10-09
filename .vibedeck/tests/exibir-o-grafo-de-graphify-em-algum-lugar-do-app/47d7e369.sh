#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
forbid $G '\.(onAppear|task)\b[^\n]*runner\.start|\.task *\{[^}]*start' "abrir a aba inicia a geração automaticamente"
need $G '"Gerar|Gerar grafo' "ação explícita Gerar ausente"
need $G '"Atualizar"' "ação explícita Atualizar ausente"
need $G 'graphify (update|extract|\.)' "geração por graphify ausente"
forbid $G 'sem IA|AST-only' "Gerar/Atualizar rodam só a parte de código ('sem IA'); a regra exige também análise semântica por IA"
grep -qE 'merging\(|AIProvider|provider|semantic|ClaudeCode|Codex' $G || bad "$G:1" "Gerar/Atualizar não usam provedor de IA para a análise semântica (ProjectGraph.merging não é chamado)"
grep -qE 'indispon|não está disponível|unavailable' $G || bad "$G:1" "indisponibilidade do provedor de IA não é informada"
exit $fail
