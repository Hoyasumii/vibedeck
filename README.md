# VibeDeck

App macOS nativo (SwiftUI + Liquid Glass) para gerenciar projetos feitos com vibe coding:
links, docs Markdown, **pontos de revisão** ("inativar esse botão", "isso não precisa aparecer agora")
agrupados por tema, **regras** que a IA precisa cumprir antes de dar uma tarefa como concluída e **ideias** futuras. Tudo fica em arquivos dentro do próprio repositório, para a IA ler e escrever também.

## Formato no seu projeto

```
<repo>/
  vibedeck.json              # declara o projeto (nome, links, reviewKinds)
  .vibedeck/
    AGENTS.md                # guia para agentes de IA (gerado)
    docs/<slug>.md
    reviews/<slug>.json      # um grupo/tema por arquivo
    rules/<slug>.json        # um tópico de regras por arquivo (paths = globs de escopo)
    ideas/<slug>.json        # uma ideia por arquivo, com regras rascunho
    agents/<slug>.json       # um agente por arquivo: nome, modelo, prompt e próximos passos
    checks/*.json            # verificações de regras registradas pelos agentes
```

## Regras e ideias

- **Tópico de regras**: lista de comportamentos (`must` bloqueia, `should` só avisa). Sem `paths`, vale
  para toda tarefa; com globs (`Sources/App/**`, `*.tsx`), vale quando um arquivo alterado casa.
- **Fluxo do agente** (exigido pelas instruções do MCP e pelo `AGENTS.md`): `rules_for` com os arquivos
  alterados → verificar cada regra → `submit_rule_check` com `pass`/`fail`/`na` para todas. Só conclui
  com `passed=true`.
- Item de revisão ligado a regras (campo `rules` ou `target.file` casando um tópico) não vai para
  `done` via CLI/MCP sem check aprovado para o item (`vibedeck review set --force` para humanos).
- **Ideias**: brainstorm com status, tags, texto markdown e regras rascunho. "Promover" cria um tópico
  de regras real com essas regras. Apagar esse tópico (no app, no Finder ou com `vibedeck ideas unpromote`)
  despromove a ideia: o vínculo some, "Aprovada" volta para "Explorando" e as regras rascunho ficam.
- **Agentes**: nome, modelo e prompt (markdown) de agentes do VibeDeck. Os **próximos passos** apontam para
  outros agentes (ou, no futuro, comandos) do VibeDeck e formam um fluxo; `vibedeck agents flow <agente>`
  (ou o botão "Copiar fluxo") gera o JSON que orquestra a IA. "Importar do Claude Code" traz os `.md` de
  `.claude/agents` (projeto e usuário).
- **Tags**: docs (frontmatter `tags: [a, b]`), revisões, regras, ideias e agentes. Cada seção da sidebar abre
  uma lista filtrável por texto e por `#tag`.

- **Claude no app**: o botão ✨ da toolbar (⇧⌘C) abre uma coluna com o Claude Code rodando na pasta do
  projeto (`claude -p` em stream-json). Ele responde em streaming, faz perguntas com opções e pede
  permissão antes de editar ou rodar comandos (Permitir, Sempre nesta sessão, Sempre em todas as sessões
  — gravado em `.claude/settings.local.json` — ou Negar). A conversa é retomada ao reabrir a janela.
  O seletor de modo (Normal, Planejar, Aceitar edições) troca o modo na hora; em Planejar, o plano
  aparece formatado para Aprovar, Aprovar e aceitar edições ou Pedir mudanças.
  O campo de mensagem tem o autocomplete do terminal: `/` lista comandos e skills (os do Claude Code,
  `.claude/commands` e `.claude/skills` do projeto e do usuário), `@` lista arquivos do projeto e outras
  conversas, e `!` roda um comando de terminal na pasta do projeto (a saída vai para a conversa e para o
  Claude na próxima mensagem). ↑/↓ navegam, Tab ou ↩ aceitam, Esc fecha.
  A aba **Terminal** do painel é um terminal interativo de verdade (SwiftTerm), com o seu shell de login
  na pasta do projeto; ele continua rodando ao trocar de aba. Programas interativos chamados com `!`
  (`vim`, `less`, `top`, `ssh`, REPLs sem script, `git commit` sem `-m`…) abrem nessa aba.
  Sem o Claude Code instalado, as opções de IA não aparecem.

Schemas: `schema/v1/` (servidos pelo Worker em `worker/`).

## Build

Requer macOS 26+ e Xcode 27 (SDK do macOS 27):

```sh
scripts/build-app.sh --install-cli   # build/VibeDeck.app + build/VibeDeck-<versão>.dmg + ~/.local/bin/vibedeck
open build/VibeDeck.app              # ou: open -a build/VibeDeck.app <pasta-do-projeto>
swift test                           # testes do Core
```

> Sem o Xcode (só Command Line Tools), o SDK 27 não compila SwiftUI: `@State` virou macro e o
> plugin `SwiftUIMacros` só vem no Xcode. Nesse caso `scripts/env.sh` cai para o SDK 26.x e os
> testes rodam com `scripts/test.sh`.

## Atalhos

| | |
|---|---|
| ⌘O | Abrir projeto |
| ⌘Z / ⇧⌘Z | Desfazer / refazer (docs têm histórico próprio, sobrevive ao autosave) |
| ⌘E | Alternar editar/ler no doc |
| ⇧⌘N | Focar campo de novo item de revisão |
| ⌥⌘I | Mostrar/ocultar painel do item |
| ⇧⌘C | Mostrar/ocultar o painel do Claude Code |

## IA

```sh
vibedeck status
vibedeck review list --status open --json
vibedeck review add "Tela de login" "Esconder link de cadastro" --kind hide --file src/Login.tsx --ai
vibedeck review set <id-ou-prefixo> --status done
vibedeck rules new "Interface" --path "Sources/VibeDeckApp/**"
vibedeck rules add interface "Nunca usar minWidth no root da janela"
vibedeck rules for Sources/VibeDeckApp/ProjectWindow.swift --json
echo '[{"ruleId":"<prefixo>","verdict":"pass","note":"..."}]' | vibedeck rules check --task "..." --item <id>
vibedeck ideas new "Modo offline" --tags futuro && vibedeck ideas promote modo-offline
vibedeck ideas unpromote modo-offline        # apaga o tópico e despromove a ideia
vibedeck agents import                       # traz os agentes do Claude Code
vibedeck agents next revisor testador        # testador atua depois do revisor
vibedeck agents flow revisor                 # JSON do fluxo para o prompt
vibedeck tag review tela-de-login ui mvp     # substitui as tags (doc | review | rules | idea)
vibedeck mcp install                         # registra o servidor MCP no Claude Code (--scope local/project/user)
vibedeck usage install                       # liga a statusline do Claude Code ao VibeDeck (mantém a atual encadeada)
vibedeck usage [--json]                      # limite da sessão (5h) e da semana, com horário de reset
vibedeck cloud check [--json]                # a main local é igual à do GitHub?
vibedeck cloud start "Corrigir o login" [--allow-dirty]   # cria uma sessão do Claude Code na nuvem
```

### Sessões na nuvem

O botão de nuvem no painel do Claude (ou `vibedeck cloud start`, ou a tool MCP `start_cloud_session`) cria uma
sessão do Claude Code na nuvem (`claude --cloud`) sobre o repositório no GitHub e abre o link no navegador.
A nuvem só vê o GitHub, então antes o VibeDeck dá `git fetch` e compara a branch padrão local com a da `origin`:
se uma estiver atrás da outra (ou se divergirem), ele para e avisa que as branches precisam ser iguais.
Alterações não commitadas só geram um aviso, que precisa ser confirmado (`--allow-dirty` / `allow_dirty`).

### Limites do Claude Code

O rodapé da sidebar mostra quanto da **sessão (5h)** e da **semana** do plano do Claude Code já foi usado e
quando cada uma reinicia. Os números vêm da statusline do Claude Code: `vibedeck usage install` (ou o botão
"Mostrar limites do Claude Code" no app) faz ela rodar `vibedeck usage record`, que grava o uso em
`~/Library/Application Support/VibeDeck/claude-usage.json`. Uma statusline que já existia continua aparecendo
(`--then`), e `vibedeck usage uninstall` a devolve. Só funciona com login de assinatura (Pro/Max); com chave de
API o Claude Code não informa limites. Agentes leem o mesmo dado pela tool MCP `claude_usage`.

## Worker (schemas)

```sh
cd worker && npm install
npm run dev        # http://localhost:8787/v1/project.schema.json
npm run deploy     # depois: scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev
```
