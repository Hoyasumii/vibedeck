---
author: ai
---
# FUN-003 — Revisões e resolução

# FUN-003 — Revisões e resolução

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Revisões agrupam pontos de ajuste por tema. Itens têm título, descrição, tipo configurável no projeto, prioridade, autoria, alvo opcional (arquivo, rota, componente, seletor), regras associadas e status open/in_progress/done/wontfix.
Descubra propõe localização e regras sem aplicar antes do aceite. Resolver no app conduz perguntas, plano, aceite e implementação; itens de grupo são tratados um por vez. Só entram itens abertos/em andamento. Esse botão não é uma operação equivalente de resolução automática disponível no CLI/MCP.

## Fluxo de uso

1. Registrar problema e alvo, se conhecido.
2. Usar Descubra opcionalmente e aceitar campos selecionados.
3. Resolver: responder perguntas e aprovar plano.
4. Implementar e verificar regras; concluir o item quando o gate correspondente estiver satisfeito.

## Regras e limites atuais a revisar

No fluxo de agentes, done exige check aplicável aprovado, inclusive manuais must exigidas para fechar o item. Falha/cancelamento do Resolver não apaga itens nem os transforma em wontfix. Autorizações e limites humanos diferem das ações da IA.

## Direção desejada já registrada

Pontos de revisão fazem parte da visão confirmada. Não há decisão de remover tipos, agrupamento ou resolução assistida.

## Decisões para o usuário

Revisar estados e tipos; decidir se o humano pode forçar conclusão, se Resolver continua exclusivo do app e como mostrar evidências antes de encerrar.

## Cenário de aceite proposto

AC-003: sem check válido, a conclusão via agente é bloqueada. Cancelar antes do aceite do plano não inicia implementação. Itens done/wontfix ficam fora do lote de resolução.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/ReviewResolve.swift](../../../../Sources/VibeDeckCore/ReviewResolve.swift)
- [Sources/VibeDeckCore/ReviewDiscover.swift](../../../../Sources/VibeDeckCore/ReviewDiscover.swift)
- [Sources/VibeDeckCore/ProjectStore.swift](../../../../Sources/VibeDeckCore/ProjectStore.swift)
- [Tests/VibeDeckCoreTests/ReviewResolveTests.swift](../../../../Tests/VibeDeckCoreTests/ReviewResolveTests.swift)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
