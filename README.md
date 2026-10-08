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
  de regras real com essas regras.
- **Tags**: docs (frontmatter `tags: [a, b]`), revisões, regras e ideias. Cada seção da sidebar abre
  uma lista filtrável por texto e por `#tag`.

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
vibedeck tag review tela-de-login ui mvp     # substitui as tags (doc | review | rules | idea)
vibedeck mcp install                         # registra o servidor MCP no Claude Code (--scope local/project/user)
```

## Worker (schemas)

```sh
cd worker && npm install
npm run dev        # http://localhost:8787/v1/project.schema.json
npm run deploy     # depois: scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev
```
