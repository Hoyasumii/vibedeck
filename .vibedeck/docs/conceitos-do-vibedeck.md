---
title: Conceitos do VibeDeck
tags: [conceitos, produto]
---

# Conceitos do VibeDeck

## O que é

O VibeDeck é um app macOS nativo (SwiftUI + Liquid Glass), acompanhado de um CLI (`vibedeck`) e de um servidor MCP (`vibedeck mcp`), para gerenciar projetos feitos com vibe coding. Tudo o que ele guarda fica **dentro do próprio repositório**, em arquivos legíveis — `vibedeck.json` e a pasta `.vibedeck/` — para que humano e IA leiam e escrevam a mesma fonte.

```
vibedeck.json          # projeto: nome, links, tipos de revisão (reviewKinds)
.vibedeck/
  AGENTS.md            # guia para agentes (gerado; não editar)
  docs/<slug>.md       # documentos
  reviews/<slug>.json  # um grupo de revisão (tema) por arquivo
  rules/<slug>.json    # um tópico de regras por arquivo
  ideas/<slug>.json    # uma ideia por arquivo
  agents/<slug>.json   # um agente do VibeDeck por arquivo
  checks/*.json        # verificações de regras (histórico; não editar)
```

## Conceitos

### Links
URLs importantes do projeto (deploy, design, artefatos, painéis), guardadas em `vibedeck.json` com título e tags. No app: adicionar com **+** ou colar uma URL (⌘V), filtrar, editar, copiar URL, remover.

### Docs
Documentos markdown em `.vibedeck/docs/<slug>.md`. O título vem do frontmatter `title:` ou do primeiro `# `; tags vêm do frontmatter `tags: [a, b]`. No app há três modos — **Editar / Dividir / Ler** (⌘E alterna) — e cada doc tem seu próprio histórico de desfazer, que sobrevive ao autosave.

### Revisões
Pontos de ajuste no produto ("inativar esse botão", "isso não precisa aparecer agora"), agrupados por **tema** (um grupo por arquivo). Cada item tem:
- `kind`: um dos `reviewKinds` do projeto (padrão: Inativar, Ocultar, Corrigir, Alterar, Remover, Nota);
- `status`: `open` → `in_progress` → `done` ou `wontfix` (Não fazer);
- `priority`: low | normal | high;
- `target` (opcional): arquivo, rota/tela, componente, seletor;
- `author`: human | ai;
- `rules` (opcional): tópicos/regras ligados ao item.

Item ligado a regras (campo `rules`, ou `target.file` casando os `paths` de um tópico) só vai para `done` com um check aprovado.

### Regras
Comportamentos que o projeto precisa manter, organizados em **tópicos**:
- `paths` vazio → o tópico vale para **toda** tarefa; com globs (`Sources/App/**`, `*.tsx`) vale quando um arquivo alterado casa;
- `severity`: **must** bloqueia a conclusão; **should** só gera aviso;
- `details`: contexto e "Verificar:" — como checar a regra de verdade.

### Checks (verificações)
Registro de que um agente verificou as regras aplicáveis a uma tarefa: um veredito `pass` / `fail` / `na` para **cada** regra, com nota de evidência. `passed=true` só quando nenhum `must` falhou. São histórico: ficam em `.vibedeck/checks/` e não se editam.

### Ideias
Planos futuros — **não** são regras ativas. Cada ideia tem `status` (new, exploring, approved, discarded, done), texto em markdown (problema, proposta, dúvidas), tags e **regras rascunho**. "Promover para Regras" cria um tópico de regras real com essas regras (aí passam a valer); "Sincronizar regras" leva regras novas para o tópico já criado. Apagar o tópico (no app, no Finder ou com `unpromote`) despromove a ideia: o vínculo some, "Aprovada" volta para "Explorando" e as regras rascunho ficam.

### Agentes
Agentes **do VibeDeck** (não do provedor de IA): `title` (nome), `model`, `prompt` em markdown, `tools` e `nextSteps` (`{kind: agent|command, ref}`) apontando para outros agentes/comandos do VibeDeck. Os próximos passos formam um fluxo, e o JSON do fluxo (`agent_flow`) orquestra a IA. Agentes do Claude Code (`.claude/agents`) podem ser importados.

### Tags
Docs, links, grupos de revisão, tópicos de regras e ideias aceitam tags. Toda lista de seção filtra por texto livre e por `#tag`.

### Autoria
Tudo registra quem criou: `human` ou `ai`. O que a IA cria é `author=ai`, e a IA nunca apaga itens, regras ou ideias de humanos.

## Cada conceito e as regras

As regras são o centro do VibeDeck: elas dizem o que precisa continuar valendo no projeto, e o **check** prova que um agente conferiu isso. Cada conceito tem um papel diferente nessa engrenagem.

### Tópico de regras — onde as regras moram
- Um arquivo `rules/<slug>.json` com título, descrição ("quando este tópico se aplica"), tags, `paths` e a lista de regras.
- **`paths` decide quando o tópico entra numa tarefa**: vazio = global (entra em **toda** tarefa e em **todo** item de revisão); com globs = só quando algum arquivo alterado casa (`Sources/App/**`, `*.tsx`).
- Cada regra tem `text` (curto e verificável), `severity` e `details` ("Como verificar"). A ordem pode ser rearranjada no app.
- **`must`** em `fail` reprova o check (`passed=false`) e impede concluir. **`should`** em `fail` vira `warning`: o check passa, mas o agente avisa o usuário.
- Se o tópico veio de uma ideia, guarda `sourceIdea`; apagar esse tópico despromove a ideia.
- No app, o inspector do tópico mostra as **verificações** registradas para ele (com ícone quando o check estava ligado a um item de revisão).

### `rules_for` — quais regras valem agora
Junta três fontes, sem repetir:
1. tópicos **globais**;
2. tópicos cujos `paths` casam com algum **arquivo alterado**;
3. tópicos **explícitos**: os passados em `topics` e, se houver item de revisão, os do campo `rules` do item + os que casam com `target.file` dele.

### Check — a prova de que as regras foram conferidas
- `submit_rule_check` recalcula as mesmas regras do `rules_for` e **exige resposta para todas** (`pass`, `fail` ou `na` + nota). Faltou alguma → erro listando as que faltaram.
- Resultado: `passed` (nenhum `must` falhou), `failures` (`must` que falharam), `warnings` (`should` que falharam).
- Fica gravado em `checks/` como histórico; um check reprovado não se corrige: envia-se outro.
- Pode estar ligado a um item de revisão (`reviewItem`), e é isso que libera o `done` do item.

### Item de revisão — o pedido que é cobrado pelas regras
- **Regras exigidas pelo item** = tópicos globais + tópicos do campo `rules` + tópicos que casam com `target.file`.
- No painel do item (⌥⌘I), seção **Regras**: um toggle por tópico. Ligar/desligar mexe no campo `rules` ("Ligar regras" / "Desligar regras", com undo). Tópicos que entram automaticamente aparecem marcados e travados, com o motivo: "Vale para toda tarefa" ou "Casa com o arquivo do item".
- Status das regras no painel: **"Regras verificadas"** (verde) ou avisos em laranja:
  - "Nenhum check registrado para este item";
  - "Falhou no último check: …";
  - "Regra nova desde o último check: …" — se alguém adicionar regra a um tópico exigido, o check antigo deixa de valer.
- Só conta o **check mais recente** ligado ao item.
- **Bloqueio do `done`**: no MCP (`update_review_item`) e no CLI (`review set --status done`), `done` falha enquanto houver problema. Humano pode forçar no CLI com `--force`. No app, o humano marca livremente; o painel só mostra o aviso ("Agentes só podem concluir este item depois de um check aprovado").
- Como os tópicos globais entram em todo item, **todo item precisa de check** enquanto existir um tópico global com regras (hoje: *Geral*).

### Ideia — regras que ainda não valem
- A ideia tem **regras rascunho** (mesmo formato: texto, severidade, detalhes), mostradas no inspector como "Rascunho: só passam a valer depois de promovidas".
- Rascunhos **nunca** entram em `rules_for`, checks ou bloqueio de `done`.
- **Promover para Regras** (só a pedido do usuário): cria um tópico com as regras da ideia (global, sem `paths`, até alguém definir escopo), liga a ideia a ele e muda o status para *Aprovada*.
- **Sincronizar regras**: com a ideia já promovida, leva para o tópico só as regras novas (por id), sem duplicar.
- **Despromover** (menu do badge "Tópico: …", `unpromote_idea`, ou apagar o tópico em qualquer lugar): o tópico some, a ideia perde o vínculo, *Aprovada* volta a *Explorando* e os rascunhos ficam na ideia.

### Docs — contexto, não regra
- Docs não viram regras nem entram em checks. Servem de referência para humanos e agentes entenderem o projeto (como este documento).
- Um doc só aparece num check se for um **arquivo alterado** e casar com os `paths` de algum tópico (tópicos globais sempre entram).
- Boa prática: a regra fica curta no tópico; a explicação longa fica num doc citado nos `details`.

### Links — referência externa
- Não têm efeito sobre regras. Servem para apontar design, deploy, artefatos e painéis que ajudam a verificar uma regra (ex.: comparar a tela com o design system).

### Tags — organização, não escopo
- Tags filtram listas (`#tag`), mas **não** decidem quais regras valem: quem decide é `paths` (e o campo `rules` do item). Um tópico com tag `ui` não é aplicado só por causa da tag.

### Autoria — quem criou e quem verificou
- Regras, itens e ideias guardam `author`; checks também (o MCP grava `ai`).
- Agentes podem **propor** regras (`add_rule`, `author=ai`), mas não apagam regras de humanos.

## Dinâmicas da interface

- **Boas-vindas**: abrir pasta (⌘O), projetos recentes; pasta sem `vibedeck.json` oferece "Inicializar projeto".
- **Janela do projeto**: sidebar com uma seção por conceito — Links, Docs, Revisões, Regras, Ideias, Agentes — em accordion (o chevron só abre/fecha, sem trocar de página); cada seção abre uma lista filtrável (texto e `#tag`); a coluna de detalhe mostra o item; o **inspector** (⌥⌘I) mostra o painel do item de revisão, as regras da ideia ou as verificações do tópico.
- **Abas**: "Abrir em Nova Aba" no menu de contexto; a barra de abas só aparece com mais de uma; clique do meio fecha; abas são persistidas e fecham sozinhas quando o item é apagado.
- **Edição direta**: não existe botão "Salvar" — cada mudança é gravada no disco na hora e pode ser desfeita (⌘Z) e refeita (⇧⌘Z). Campos de texto confirmam no Return ou ao perder o foco.
- **Ao vivo**: alterações feitas fora do app (CLI, MCP, IA, editor de texto) aparecem automaticamente; no doc, entram como edição desfazível ("Alteração externa").
- **Atalhos**: ⌘O abrir projeto · ⌘Z / ⇧⌘Z desfazer/refazer · ⌘E editar/ler doc · ⇧⌘N novo item de revisão · ⌥⌘I painel do item.

## Funcionamento

- **VibeDeckCore** (`ProjectStore`) não guarda estado: toda operação lê e grava no disco, com escrita atômica e JSON tolerante a arquivos editados à mão.
- **App**: o `ProjectModel` é um espelho em memória que grava cada mudança imediatamente e observa a pasta (FSEvents) para aplicar mudanças externas.
- **CLI e MCP** expõem as operações do Core para humanos e agentes; o MCP carrega nas instruções o fluxo obrigatório de regras.
- **Schemas** JSON (`schema/v1`) descrevem cada arquivo e são servidos por um Worker.

## Fluxo padrão

### Humano
1. Abre o projeto no app.
2. Registra o que viu: itens de revisão por tema, regras que o projeto deve manter, ideias para o futuro, links e docs.
3. Pede à IA para trabalhar (num item, numa área, numa ideia).

### IA (agente)
1. Lê os itens de revisão abertos da área antes de mexer.
2. Marca o item como `in_progress`.
3. Implementa.
4. Chama `rules_for` com os arquivos alterados (e o item, se houver).
5. Verifica cada regra contra o código de verdade.
6. Envia `submit_rule_check` com `pass`/`fail`/`na` para **todas** as regras.
7. Se `passed=false`, corrige e envia de novo. Só conclui com `passed=true`.
8. Marca o item como `done` e avisa o usuário sobre regras `should` que falharam.
9. Registra com `add_idea` ideias que surgirem no caminho.

### Ideia → regra
`new` → `exploring` → `approved` → **promover** (só a pedido do usuário) → as regras rascunho viram um tópico ativo → passam a ser cobradas nos checks.
