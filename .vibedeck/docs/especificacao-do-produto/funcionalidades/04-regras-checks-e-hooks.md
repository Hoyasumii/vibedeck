---
author: ai
---
# FUN-004 — Regras, checks e hooks

# FUN-004 — Regras, checks e hooks

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Regras são agrupadas em tópicos, com texto, detalhes, tags, escopo por paths e severidade must/should. Tópicos sem paths são globais. rules_for reúne globais, tópicos por arquivos e referências explícitas, incluindo contexto da revisão.
Scripts válidos são executados pelo runner: exit 0=pass, 77=na, demais=fail. Recebem raiz, ID da regra e arquivos afetados. Há timeout, cancelamento, concorrência limitada e serialização por ferramenta de build.
submit_rule_check executa scripts e grava histórico. Manuais ficam pending no fluxo automático; verificação manual explícita exige evidências. must falhando bloqueia; should falhando gera aviso. Alterar regra invalida seu teste por hash.

## Fluxo de uso

1. Consultar regras do escopo.
2. Executar scripts e registrar check.
3. Corrigir falhas must e enviar novo check.
4. Quando solicitado ou necessário ao fechamento de revisão, verificar manuais.
5. O hook Stop instalado cobra check posterior às alterações e correspondente ao escopo.

## Regras e limites atuais a revisar

Check histórico não é editado para mudar resultado. Teste ausente/desatualizado não é aprovação automática. Tags não definem aplicabilidade. A cobertura de checks não prova, sozinha, ausência de qualquer regressão.

## Direção desejada já registrada

Piloto de verificações Rust e futura biblioteca compartilhada, mantendo o contrato e sem compilar a cada regra. Converter todos os scripts de uma vez não foi definido como pré-requisito.

## Decisões para o usuário

Revisar geração de testes, scripts arbitrários versus verificações embutidas, manuais, hashes, prazo/concorrência, política do hook e portabilidade de dependências.

## Cenário de aceite proposto

AC-004: must fail reprova; should fail avisa; 77 vira na. Manual permanece pending sem verificação explícita. Regra alterada não reutiliza teste como se fosse atual.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/RuleTests.swift](../../../../Sources/VibeDeckCore/RuleTests.swift)
- [Sources/VibeDeckCore/RuleExecution.swift](../../../../Sources/VibeDeckCore/RuleExecution.swift)
- [Sources/VibeDeckCore/StopGate.swift](../../../../Sources/VibeDeckCore/StopGate.swift)
- [Sources/VibeDeckCore/ProjectStore.swift](../../../../Sources/VibeDeckCore/ProjectStore.swift)
- [.vibedeck/AGENTS.md](../../../../.vibedeck/AGENTS.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
