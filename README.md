# VibeDeck

App macOS nativo (SwiftUI + Liquid Glass) para gerenciar projetos feitos com vibe coding:
links, docs Markdown e **pontos de revisão** ("inativar esse botão", "isso não precisa aparecer agora"),
agrupados por tema. Tudo fica em arquivos dentro do próprio repositório, para a IA ler e escrever também.

## Formato no seu projeto

```
<repo>/
  vibedeck.json              # declara o projeto (nome, links, reviewKinds)
  .vibedeck/
    AGENTS.md                # guia para agentes de IA (gerado)
    docs/<slug>.md
    reviews/<slug>.json      # um grupo/tema por arquivo
```

Schemas: `schema/v1/` (servidos pelo Worker em `worker/`).

## Build

Requer macOS 26+ e Xcode 27 (SDK do macOS 27):

```sh
scripts/build-app.sh --install-cli   # build/VibeDeck.app + ~/.local/bin/vibedeck
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
claude mcp add vibedeck -- vibedeck mcp     # servidor MCP (stdio)
```

## Worker (schemas)

```sh
cd worker && npm install
npm run dev        # http://localhost:8787/v1/project.schema.json
npm run deploy     # depois: scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev
```
