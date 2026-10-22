---
author: ai
---
# Especificação do produto VibeDeck

Estado: **rascunho preenchido para revisão humana**, com base no repositório inspecionado em 22/10/2026. Não é aprovação automática do produto atual nem da migração.

## Como revisar

Comece pela [visão do produto](01-visao-do-produto.md), com suas respostas preservadas, e depois pelo [inventário de funcionalidades](02-inventario-de-funcionalidades.md). Cada área tem documento próprio com comportamento atual, fluxo, limites, direção desejada, decisões abertas e cenário de aceite candidato.
Você pode retirar recursos, escrever mudanças e responder às decisões. Para deixar a intenção clara, use “manter”, “mudar para”, “retirar” ou “decidir depois”.
Mudanças na especificação descrevem o destino desejado; retirar uma descrição não autoriza, por si só, excluir dados, mudar regras ativas ou apagar a implementação imediatamente.

## Documentos

1. [Visão e objetivo](01-visao-do-produto.md).
2. [Inventário e mapa das 12 áreas](02-inventario-de-funcionalidades.md).
3. [Exemplo preenchido e modelo de funcionalidade](03-modelo-de-funcionalidade.md).
4. [Contratos e diferenças entre atual e futuro](04-contratos-e-compatibilidade.md).
5. [Cenários de aceite candidatos](05-criterios-de-aceite.md).
6. [Decisões e sequência de migração](06-decisoes-e-migracao.md).
7. [Mudanças confirmadas: início guiado, Docs vinculados e local/SSH](07-mudancas-confirmadas.md).
8. [Stack e padrões cadastrados do projeto](08-stack-e-padroes-do-projeto.md).
9. [Prompt de coordenação da implementação do Core/CLI/MCP em Rust](09-prompt-de-implementacao-do-core-rust.md).
10. [Atualização automática do app, CLI e MCP](10-atualizacao-automatica.md) — fora da primeira versão.
11. [Prompt de implementação da nova interface](11-prompt-de-implementacao-da-interface.md).
12. [Prompt mestre: Core/CLI/MCP + Site + App macOS](12-prompt-mestre-core-interface-site.md) — coordena 09 e 11 num só pedido.

## Legenda

- **Atual observado:** comportamento recuperado de código, guia e documentação atuais. Pode ser alterado por decisão sua.
- **Direção confirmada:** objetivo explicitado por você nesta conversa ou na visão.
- **Proposta para revisão:** síntese ou critério sugerido pela IA, sem aceite humano presumido.
- **Pendente:** decisão que as fontes não resolvem.
- **Histórico/limitação:** detalhe que não deve ser copiado automaticamente para Rust.

Em todos os documentos de funcionalidades, os cenários são propostos; não representam testes executados nesta tarefa. A coleta foi estática, sem abrir a interface nem rodar sessões de nuvem ou providers.

## Direção confirmada

Facilitar desenvolvimento assistido por IA com ideias, documentação, stack/padrões, regras e revisões; reutilizar agentes, comandos, skills e workflows.
Migrar Core, CLI e MCP para Rust; viabilizar MCP por stdio em outras máquinas, em execução local ou por SSH com pouca preparação. Manter a interface macOS como cliente do Core. A visão humana contém a referência visual; seu conteúdo não foi validado nesta coleta.
Claude/Codex são os providers implementados; OpenCode aparece como expansão desejada. A troca automática de provider, o transporte HTTP remoto e uma nova UI Windows/Linux não estão aprovados como implementação pronta.

## Consulta pela IA antes de executar uma ideia

Ler este índice, a ideia, a [stack e os padrões cadastrados](08-stack-e-padroes-do-projeto.md) e as decisões relacionadas. Reler o cadastro via MCP antes de implementar para detectar atualizações. Abrir as áreas/contratos necessários pelo inventário; buscar código/testes se houver divergência. A especificação revisada define o destino pretendido, mas conflitos com regras ativas exigem decisão e atualização explícitas antes da alteração.
Preservar textos humanos, IDs, requisitos, falhas pendentes e workflow. Campos ainda abertos, propostas e exemplos não são aprovação.
Este diretório complementa AGENTS.md, regras, testes e avaliação das ideias; não substitui esses gates nem autoriza promoção automática.

## Ordem das ideias

| Etapa | Entrega | UUID |
| --- | --- | --- |
| 01 | Arquitetura e padrões | 32390FB1-061D-45DE-ACC8-24D717FF880A |
| 02 | Core mínimo/MCP local e por SSH | 6AC91755-1DDC-487F-9554-344E0E95C258 |
| 03 | Piloto de 3 a 5 verificações Rust | 5FE68368-901F-4643-8A35-427C7EBEE15B |
| 04 | Concluir Core/CLI/MCP e integrar app | 35806341-8605-43B0-A13A-456DB1369B35 |
| 05 | Medir e melhorar desempenho | C17132D2-9CAA-4981-A4B5-81CBE4550AA8 |

## Situação da revisão

Textos humanos do documento 01: preservados.
Demais sínteses: propostas pela IA, aguardando sua leitura.
Implementação iniciada por este preenchimento: nenhuma.
Decisões bloqueantes: ver documento 06; principalmente ambiente SSH, plataformas, distribuição, amostra MCP e destino de cada funcionalidade.

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.

No mesmo dia foi pedida a atualização automática do app (MUD-004) e, em seguida, adiada: **fica fora da primeira versão**. Requisitos, pré-requisitos e decisões para a versão posterior em [10 — Atualização automática](10-atualizacao-automatica.md).
