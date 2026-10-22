---
author: ai
---
# FUN-005 — Workflows e execuções

# FUN-005 — Workflows e execuções

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Workflow possui entrada, etapas de agente/comando/skill e transições por veredito, condição em linguagem natural ou fallback. A primeira etapa é o início; nextSteps dos itens não governa o workflow. Há limites maxSteps e maxVisits.
Execuções persistem etapa, histórico, perguntas, respostas, provider e checkpoints em runs/. O motor do VibeDeck controla a execução nos dois provedores; cada etapa usa contexto próprio. Checkpoint de saída concluída precede a avaliação de condições. Retomar preserva estado; reiniciar é uma ação distinta.

## Fluxo de uso

1. Selecionar workflow e entrada.
2. Iniciar ou retomar execução.
3. Executar etapa; registrar saída/perguntas.
4. Receber e persistir respostas antes de continuar.
5. Avaliar transição ou encerrar; interromper ao atingir limites.

## Regras e limites atuais a revisar

Execução mantém provider; não há troca automática. Mudança do título de ideia não quebra vínculo por UUID. Ordem de seleção: veredito, condição, fallback. Sem transição aplicável, encerra.

## Direção desejada já registrada

Workflows são centrais para orquestrar tarefas reutilizáveis na visão humana. Alterações de formato/semântica ainda não foram definidas.

## Decisões para o usuário

Revisar forma de editar fluxos, persistência, retomar/reiniciar, tratamento de perguntas e se futuras trocas de provider exigem novo ciclo ou migração explícita.

## Cenário de aceite proposto

AC-005: interromper após checkpoint e retomar conserva saída, etapa, provider e respostas; reiniciar limpa o estado conforme contrato. Limites impedem execução infinita.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/Workflows.swift](../../../../Sources/VibeDeckCore/Workflows.swift)
- [Sources/VibeDeckCore/WorkflowRuns.swift](../../../../Sources/VibeDeckCore/WorkflowRuns.swift)
- [Sources/VibeDeckCore/AIWorkflowRunner.swift](../../../../Sources/VibeDeckCore/AIWorkflowRunner.swift)
- [Tests/VibeDeckCoreTests/WorkflowRunsTests.swift](../../../../Tests/VibeDeckCoreTests/WorkflowRunsTests.swift)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
