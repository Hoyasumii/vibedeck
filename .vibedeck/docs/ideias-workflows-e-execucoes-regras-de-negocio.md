---
author: ai
---
# Ideias, workflows e execuções: regras de negócio

Fontes: `README.md:131-168`; conceitos básicos em `.vibedeck/docs/conceitos-do-vibedeck.md`.

## Implementar uma ideia

- Na etapa da descrição, a IA também diz se a ideia é **viável** ou o que falta; o veredito fica em `readiness` (`README.md:135-137`).
- O botão "Implementar" só habilita com regras e veredito viável e atual. Mudanças em título, texto, globs ou regras invalidam o veredito, e "Verificar" refaz só essa avaliação (`README.md:137-138`).
- Ao clicar, as regras são promovidas/sincronizadas (a ideia fica "Aprovada") e a IA recebe no chat o pedido de implementar seguindo as regras e o check (`README.md:138-139`).
- "Promover": se o tópico já existe, os globs são somados; globs que não casam mais arquivo são avisados antes (`README.md:131-133`).

## Agentes, comandos e skills

- Os **próximos passos** formam um fluxo; `vibedeck agents|commands|skills flow <nome>` gera o JSON que orquestra a IA (`README.md:140-153`).
- Importações: agentes de `.claude/agents` e `.codex/agents/*.toml`; comandos de `.claude/commands` (subpastas viram namespace, como `git/commit.md` → `git:commit`) e de `.codex/prompts`; skills de `.claude/skills` (`README.md:142-153`).

## Workflows

- Cada etapa roda um agente, comando ou skill. A primeira é o início (`README.md:154-156`).
- Ordem de avaliação das transições: **veredito** (última linha do resultado, como "= APROVADO"), depois **condição** (linguagem natural) e por fim um "senão" opcional (`README.md:156-158`).
- Sem transição válida, o workflow termina. `maxSteps` (padrão 25) e `maxVisits` por etapa evitam laço infinito (`README.md:158-160`).

## Execuções

- "Executar" cria a execução em `.vibedeck/runs/<workflow>/<entrada>/` (`README.md:163`; estrutura em `README.md:27`).
- Claude usa o chat como orquestrador e um subagente por etapa. No Codex, o VibeDeck controla a execução e abre uma thread limpa por etapa (`README.md:164-166`).
- O provedor fica gravado na execução, e continuar mantém esse provedor (`README.md:166`).
- As respostas às perguntas das etapas são registradas antes da retomada (`README.md:167`).

## Conduzir (apenas neste repositório)

Fluxo com issues do GitHub (e o Status do GitHub Projects). Comandos: `registrar-task-do-github → viabilizar → planejar → criticar → implementar → avaliar → abrir-pull-request`, e `buscar-review` para PR já publicado (`README.md:169-173`). Requer `gh auth refresh -s project` (`README.md:173`).