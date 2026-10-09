---
author: ai
---
# Como rodar e compilar o VibeDeck

Fontes: `README.md`, `Package.swift`, `scripts/build-app.sh`, `scripts/env.sh`, `scripts/test.sh`, `.github/workflows/swift.yml`.

## Requisitos

- macOS 26 ou superior como plataforma do pacote (`Package.swift:6`, `swift-tools-version: 6.2` em `Package.swift:1`).
- O README pede macOS 26+ e Xcode 27 (SDK do macOS 27) (`README.md:214`).
- Sem o Xcode (só Command Line Tools), o SDK 27 não compila SwiftUI porque o plugin `SwiftUIMacros` só vem no Xcode (`README.md:222-224`). Nesse caso `scripts/env.sh` usa o SDK macOS 26.x mais recente (`scripts/env.sh:4-9`).

## Produtos do pacote

Definidos em `Package.swift:7-11`:

| Produto | Tipo |
|---|---|
| `VibeDeckApp` | executável (app SwiftUI) |
| `vibedeck` | executável (CLI e servidor MCP) |
| `VibeDeckCore` | biblioteca |

## Gerar o app e o CLI

```sh
scripts/build-app.sh --install-cli
open build/VibeDeck.app
```

(`README.md:217-218`). O script (`scripts/build-app.sh`):

- Faz build `release` por padrão; `CONFIG=debug` gera build de debug (`scripts/build-app.sh:6,11`).
- Compila `VibeDeckApp` e `vibedeck` (`scripts/build-app.sh:14-15`).
- Monta `build/VibeDeck.app` com o CLI em `Contents/Helpers/vibedeck`, ícone e fontes (`scripts/build-app.sh:18-28`).
- Lê a versão de `Sources/vibedeck/CLI.swift` (`scripts/build-app.sh:12`).
- Assina com `codesign --sign -` (assinatura ad hoc) (`scripts/build-app.sh:52`).
- Gera o instalador `build/VibeDeck-<versão>.dmg` (`scripts/build-app.sh:55-97`).
- Com `--install-cli`, cria o link simbólico `~/.local/bin/vibedeck` (`scripts/build-app.sh:99-103`).

Abrir um projeto direto: `open -a build/VibeDeck.app <pasta-do-projeto>` (`README.md:218`).

## Fonte do terminal

O terminal usa a JetBrains Mono Nerd Font Mono, copiada para `Contents/Resources/Fonts` pelo `build-app.sh`. Com `swift run`, cai para a fonte monoespaçada do sistema (`README.md:226-228`).

## Testes

- `swift test` roda os testes (`README.md:219`). O CI usa exatamente `swift test` (`.github/workflows/swift.yml:21`).
- `scripts/test.sh` é pensado para ambiente só com Command Line Tools. Compila apenas o alvo `VibeDeckCoreTests` e roda `swift test --skip-build` (`scripts/test.sh:6-7`).
- Alvos de teste: `VibeDeckCoreTests` e `VibeDeckAppTests` (`Package.swift:38-43`).
- Renderizador do grafo: `node scripts/test-graph-renderer.cjs` (`README.md:187`).
- Eficiência de IA: `scripts/test-ai-efficiency.sh` (`README.md:384`).

## Build só do CLI/MCP (Linux)

`swift build -c release --product vibedeck` compila sem o app SwiftUI. O CI valida isso num contêiner `swift:6.2` (`.github/workflows/swift.yml:24-29`; `README.md:326`).

## CI

O workflow `Swift` roda em push na `main`, em pull requests e manualmente, ignorando mudanças em `worker/**` (`.github/workflows/swift.yml:3-9`). O job `test` usa `macos-latest` com Xcode `latest-stable` (`.github/workflows/swift.yml:13-18`).

## Worker de schemas

```sh
cd worker && npm install
npm run dev      # http://localhost:8787/v1/project.schema.json
npm run deploy
```

Depois do deploy: `scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev` (`README.md:342-348`). Os schemas ficam em `schema/v1/` (`README.md:210`).