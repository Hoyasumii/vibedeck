---
author: ai
---
# Dependências e requisitos externos

Fontes: `Package.swift`, `README.md`, `scripts/build-app.sh`.

## Dependências Swift (SwiftPM)

Declaradas em `Package.swift:12-18`:

| Pacote | Versão | Uso (alvo) |
|---|---|---|
| `swift-argument-parser` | `from: 1.8.0` | produto `ArgumentParser`, no alvo `vibedeck` (`Package.swift:34`) |
| `modelcontextprotocol/swift-sdk` | `from: 0.12.0` | produto `MCP`, no alvo `vibedeck` (`Package.swift:35`) |
| `swift-markdown-ui` | `from: 2.4.0` | produto `MarkdownUI`, no alvo `VibeDeckApp` (`Package.swift:25`) |
| `SwiftTerm` | `.upToNextMinor(from: "1.11.0")` | no `VibeDeckApp` e nos testes do app (`Package.swift:26,41`) |

O comentário em `Package.swift:16` explica o limite do SwiftTerm: a versão 1.12+ traz um shader Metal, que exige o Metal Toolchain baixado separadamente para compilar.

## Alvos

- `VibeDeckCore`: copia o recurso `GraphResources` (`Package.swift:20`).
- `VibeDeckApp`: depende de `VibeDeckCore`, `MarkdownUI` e `SwiftTerm`, em modo de linguagem Swift 5 (`Package.swift:21-29`).
- `vibedeck`: depende de `VibeDeckCore`, `ArgumentParser` e `MCP` (`Package.swift:30-37`).

## Ferramentas externas

- **Claude Code** (`claude`): usado no chat com `claude -p` em stream-json (`README.md:189`) e em `claude --cloud` (`README.md:319-320`).
- **Codex CLI**: o painel usa `codex app-server --stdio` (`README.md:189-190`). Requer App Server e autenticação local com `codex login` (`README.md:293`). Para o modo Auto, é preciso um Codex CLI com suporte a Auto-review (`README.md:196`).
- As ações de IA funcionam com apenas um dos provedores instalado. Os registros continuam acessíveis sem IA (`README.md:208`).
- **Python 3**: o instalador do adaptador MCP para Codex exige Python 3 (`README.md:309-310`).
- **GitHub CLI**: o fluxo "Conduzir" exige `gh auth refresh -s project` (`README.md:173`).
- **Node/npm**: para o Worker (`README.md:344-347`) e para o teste do renderizador do grafo (`README.md:187`).
- **Skill Icons MCP**: o catálogo de ícones da Stack vem do servidor MCP do Skill Icons, com cache em `~/Library/Caches/VibeDeck/skill-icons` (`README.md:38-40`).

## Dados locais gravados fora do repositório

- Uso do Claude Code: `~/Library/Application Support/VibeDeck/claude-usage.json` (`README.md:333`).
- Métricas e snapshots de IA: Application Support/VibeDeck/ai, separados por diretório de projeto, sem telemetria (`README.md:380-382`).

O `README.md` não documenta nenhum segredo ou variável de ambiente obrigatória para o app.