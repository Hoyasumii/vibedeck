---
author: ai
---
# FUN-002 — Ideias, avaliação e dependências

# FUN-002 — Ideias, avaliação e dependências

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Ideias guardam título, descrição Markdown, tags, globs sugeridos, regras rascunho e status new/exploring/approved/discarded/done. A avaliação de viabilidade/readiness corresponde ao conteúdo atual; alterações relevantes invalidam a avaliação.
Salvar avaliação viável com regras pode aprovar a ideia, mas não promove regras. Promover e despromover são operações distintas. Dependências apontam para UUIDs; dependência ausente ou ainda não done bloqueia implementar. O Core recusa ciclos, autorreferência e referências inexistentes.

## Fluxo de uso

1. Registrar e refinar problema, proposta, escopo e critérios.
2. Consultar Descubra/Verificar; revisar e salvar avaliação.
3. Resolver dependências e escolher implementação padrão ou workflow, quando o app oferece essa escolha.
4. Executar a ideia com as validações exigidas. Cancelar a escolha não inicia trabalho nem promove.

## Regras e limites atuais a revisar

Ideia não é regra ativa. Aprovação, promoção, avaliação e conclusão têm significados diferentes. Dependências bloqueiam implementação; não impedem refinar/aprovar. Copiar prompt não inicia execução.

## Direção desejada já registrada

Usuário quer ideias que amadureçam funcionalidades e limites e alimentem regras do projeto. O nível de automação desse vínculo ainda deve ser revisado.

## Decisões para o usuário

Revisar se manter readiness, regras obrigatórias para implementar e promoção separada. Definir quando concluir automaticamente uma ideia e como expor dependências.

## Cenário de aceite proposto

AC-002: editar conteúdo invalida readiness; dependência pendente bloqueia antes de criar execução; ciclo é recusado sem escrita. Concluir dependência apenas libera a ação, sem dispará-la.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/Rules.swift](../../../../Sources/VibeDeckCore/Rules.swift)
- [Sources/VibeDeckCore/ProjectStore.swift](../../../../Sources/VibeDeckCore/ProjectStore.swift)
- [Tests/VibeDeckCoreTests/RulesTests.swift](../../../../Tests/VibeDeckCoreTests/RulesTests.swift)
- [Tests/VibeDeckCoreTests/WorkflowRunsTests.swift](../../../../Tests/VibeDeckCoreTests/WorkflowRunsTests.swift)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
