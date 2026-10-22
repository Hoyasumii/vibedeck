---
author: ai
---
# FUN-006 — Agentes, comandos, skills e kits

# FUN-006 — Agentes, comandos, skills e kits

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

São registros próprios do VibeDeck, não cópias automaticamente sincronizadas dos provedores. Têm prompt e configurações; comandos aceitam argumentos; skills descrevem quando usar. nextSteps encadeia referências a registros existentes.
Há importação de formatos Claude/Codex e consulta dos fluxos pelo CLI/MCP. Criar/Editar com IA propõe conteúdo antes do aceite no app. Catálogos oferecem conjuntos de agentes, comandos, skills e workflows. Itens adicionados são cópias editáveis, com slugs únicos e referências remapeadas.

## Fluxo de uso

1. Criar, importar ou selecionar itens de um kit.
2. Revisar conteúdo/configurações e confirmar.
3. Reutilizar isoladamente, por nextSteps ou como etapa de workflow.
4. Editar a cópia local sem alterar automaticamente a origem do provedor.

## Regras e limites atuais a revisar

Abrir catálogo não instala nada. Importar não deve sobrescrever sem autorização correspondente. Referências apontam para itens VibeDeck; recursos de apoio de skills importadas continuam recuperáveis pelo caminho da origem.

## Direção desejada já registrada

A visão humana quer espelhar os conceitos de agentes/skills/comandos e utilizá-los no VibeDeck. Sincronização bidirecional e suporte a novos provedores não estão confirmados.

## Decisões para o usuário

Revisar necessidade de nextSteps versus workflows, escopo de importação/exportação, atualização de cópias, configuração de modelo/tools e quais kits manter.

## Cenário de aceite proposto

AC-006: adicionar kit duas vezes não sobrescreve o primeiro; referências da segunda cópia são coerentes. Rejeitar proposta de IA não grava item.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/Agents.swift](../../../../Sources/VibeDeckCore/Agents.swift)
- [Sources/VibeDeckCore/Commands.swift](../../../../Sources/VibeDeckCore/Commands.swift)
- [Sources/VibeDeckCore/Skills.swift](../../../../Sources/VibeDeckCore/Skills.swift)
- [Sources/VibeDeckCore/KitCatalog.swift](../../../../Sources/VibeDeckCore/KitCatalog.swift)
- [.vibedeck/guide.md](../../../../.vibedeck/guide.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
