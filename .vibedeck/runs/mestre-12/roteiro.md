# Plano — Prompt mestre 12: Core/CLI/MCP Rust + Site + App macOS

## Contexto
O doc 12 (`.vibedeck/docs/especificacao-do-produto/12-prompt-mestre-core-interface-site.md`) pede a entrega coordenada de três trilhas: novo Core em Rust com CLI e MCP stdio (CORE, doc 09), worker de schemas (SITE) e a interface V2 do app macOS 26 (APP, doc 11). Hoje tudo é Swift (~33,7k linhas: `Sources/VibeDeckCore`, `Sources/vibedeck` com CLI.swift/MCPServer.swift ~100 ferramentas, `Sources/VibeDeckApp`). O container é Linux (Rust 1.97, Node 22; sem Swift, sem `vibedeck`). Etapa 0 concluída; decisões abaixo foram respondidas pelo usuário em 2026-10-22.

## Decisões confirmadas (gravar em `.vibedeck/runs/mestre-12/estado.md`)
| ID | Decisão |
|---|---|
| D-AMB-1 | APP verificada pela CI macOS (`.github/workflows/swift.yml`, macos-latest) via **PR draft** deste branch |
| D-AMB-2 | **Ignorar CLI/MCP `vibedeck`**: sem `rules_for`/`submit_rule_check`/`workflow_run_*`/`list_stack`. Gates de regras e workflow não rodam; registrar como limitação no relatório (não como aprovação). Stack/padrões lidos de `.vibedeck/` e doc 08 |
| D-GIT | Commit coeso por fatia + `git push -u origin claude/peaceful-rubin-0mtjcy` |
| D-EST | Estado/roteiro em `.vibedeck/runs/mestre-12/` (estado.md ≤ 80 linhas, roteiro.md); logs grandes fora do Git (`.gitignore` local do dir) |
| D1/D2 | V2 é o alvo; revisar regras 047D2216, 492100C1, 335DA4F8, 3901FA3E, 34D2EA32, A999B857 para a V2 (editando os JSON em `.vibedeck/rules/`, author=ai); B382469C mantida; filtro no topo da coluna de conteúdo |
| D3 | Início guiado: Novo projeto ou pasta sem `vibedeck.json`; "Pular" retomável em Projeto › Visão geral; varre `.claude/agents|commands|skills` e `.codex/prompts`; duplicados "já cadastrado", desmarcados |
| D4 | Docs vinculados **automáticos**: todo `.md` da raiz vira symlink relativo em `.vibedeck/docs/`; edição grava na origem mantendo o link; quebrado → aviso + remover vínculo; colisão → sufixo `-raiz`; nunca seguir links para fora do projeto |
| D5 | Nuvem: **remover e limpar dados** (comandos, ferramentas MCP, UI, `codexCloudEnvironment`, históricos de nuvem) |
| D6 | Reusar ícones `terminal`/`link`; providers só Claude/Codex |
| D7 | macOS universal (arm64+x86_64) + Linux x86_64/aarch64 musl; Windows depois |
| D8 | Prova SSH com `sshd` local em container + máquina limpa (container sem toolchain) |
| D9 | Fronteira SwiftUI↔Rust: **processo + JSON** (mesmo binário; modo stdio persistente), confirmado pela prova da fase 01 |
| D10 | Site = só worker de schemas; workflow de Releases preparado, sem publicar; sem auto-update |
| D11 | Paridade total de dados (schemas v1, IDs, ordem de campos); exceções: nuvem e symlinks |
| D12 | Após paridade e app no Rust, remover `VibeDeckCore` e target `vibedeck` do `Package.swift` |
| D13 | Subagentes (líderes/executores/verificadores) em Sonnet; coordenador no modelo atual |

Ainda abertas (decisão técnica minha na fase 01, registrada com justificativa): operações mínimas MCP (DEC-004), 3–5 regras do piloto (DEC-005), papel do Zod.

## Estrutura alvo
- `Cargo.toml` (workspace na raiz) + `crates/vibedeck-core` (domínio, persistência JSON compatível, rules runner, SSH), `crates/vibedeck-cli` (binário `vibedeck`: CLI clap + `vibedeck mcp` stdio + `vibedeck serve --json` para o app). Divisão final decidida na fase 01, sem crate por padrão.
- `schema/v1/*.schema.json`: fonte dos contratos (dono CORE). `worker/` consome via `npm run sync`.
- `Sources/VibeDeckApp/`: V2 + `CoreClient.swift` (ponte processo/JSON, dono único: líder APP após contrato aprovado).
- CI: `.github/workflows/rust.yml` (fmt/clippy/test Linux+macOS, build musl/universal como artefato); `swift.yml` existente valida APP.

## Fases e fatias
**Etapa 0 (feito)** → criar `.vibedeck/runs/mestre-12/estado.md` + `roteiro.md` com as decisões acima; abrir PR draft para ativar CI macOS.

**CORE F01 — Arquitetura e contratos** (líder Sonnet; executores por área)
- Inventário da superfície: comandos/flags/exit codes de `Sources/vibedeck/CLI.swift`, `AICommands.swift`, `ItemGroupCommands.swift`, `ReorganizeCommands.swift`; ferramentas MCP de `MCPServer.swift`; formatos de `Models.swift`/`ProjectStore.swift`. Saída: `roteiro.md` com matriz das 12 áreas (manter/mudar/remover conforme D3–D5).
- Baseline de contrato: job na CI macOS roda `scripts/mcp-contract.py <swift-bin> snapshot` e publica o snapshot como artefato → commitado em `Tests/fixtures/mcp-contract/` para comparar com o Rust.
- Fixtures: cópia do `.vibedeck/` deste repo (round-trip byte-a-byte).
- Prova da fronteira: protótipo `vibedeck serve --json` + `CoreClient.swift` mínimo, validado pela CI macOS.

**APP-1 (paralelo à F01)** — `DesignTokens.swift` + componentes a partir de `design/prototipo/` (tokens `:root`, `vendor/vibedeck-components.js`); validado por `swift build`/`swift test` na CI.

**CORE F02 — Core/CLI/MCP mínimo + SSH**: fatia vertical leitura+escrita (escolhidas na F01) pelo mesmo caso de uso no CLI e MCP; stdout só protocolo; erros estruturados; build musl estático; prova em container limpo e via `sshd` local.

**SITE-1** — schemas v1 validados contra os contratos da F01 (script de validação JSON Schema em `worker/`), `npm run typecheck`, `npx wrangler dev` testando `/`, `/v1`, cada schema, CORS, 405 (script curl em `worker/scripts/`). Sem deploy.

**CORE F03 — Piloto de 3–5 regras em Rust** (válido, erro, não-aplicável) com paridade contra os scripts atuais de `.vibedeck/checks`.

**APP-2** — janela V2 (trilho, painel IA ⇧⌘C, barra de status Local/SSH), telas das pranchas 13–38, onboarding (D3), Docs vinculados (D4); ligadas ao Core Rust por área conforme ficam prontas. Revisão das regras de interface (D2) antes desta fatia.

**CORE F04 — Paridade completa**: todas as ferramentas/comandos exceto nuvem (removidos, D5, com limpeza de dados); symlinks de Docs (D4); `mcp-contract.py check` contra o baseline (diferenças só nas exceções D5); onboarding/discovery no Core.
→ **APP-3**: remover UI antiga (V1, `CloudLaunchSheet.swift`, etc.) e nuvem; app usa só Rust → remover `VibeDeckCore`/target `vibedeck` (D12), ajustar `scripts/test.sh`/`build-app.sh`.

**CORE F05 — Desempenho**: medir startup, `tools/list`, rules check; otimizar onde medir.

## Gates por fatia
1. Rust: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` (Linux local + CI macOS). Swift: CI `swift test` verde. Site: `npm run typecheck` + script de rotas.
2. Verificador Sonnet independente → `APROVADO`/`AJUSTAR` com evidência (registrado em estado.md; sem `workflow_run_record`, D-AMB-2).
3. `graphify update .` — indisponível no container; registrar como pulado.
4. Regras VibeDeck — puladas por D-AMB-2; listar no relatório.
5. Commit + push por fatia; acompanhar CI do PR draft.

## Arquivos críticos
- Ler: `Sources/vibedeck/{CLI,MCPServer}.swift`, `Sources/VibeDeckCore/{Models,ProjectStore,Rules,RuleExecution,SSHConnection,RemoteExecution,CloudSession}.swift`, `scripts/mcp-contract.py`, `schema/v1/*`, `worker/src/index.ts`, `design/prototipo/`.
- Criar: `Cargo.toml`, `crates/**`, `.github/workflows/rust.yml`, `Sources/VibeDeckApp/{DesignTokens,CoreClient}.swift`, `.vibedeck/runs/mestre-12/*`.
- Alterar: `Package.swift` (F04/APP-3), `.vibedeck/rules/*` (D2), `Sources/VibeDeckApp/*`.

## Verificação ponta a ponta
- `cargo test` + `scripts/mcp-contract.py target/release/vibedeck check Tests/fixtures/mcp-contract` (paridade MCP).
- Cliente MCP real (handshake/list/call) local, em container limpo e via `ssh localhost vibedeck mcp`.
- Round-trip das fixtures `.vibedeck/` sem diff.
- CI do PR draft: Swift (app usando Rust) e Rust verdes em macOS/Linux.
- `cd worker && npm run typecheck && npx wrangler dev` + script de rotas.

## Execução
Ao aprovar: mudar para modo auto e seguir a ordem acima, atualizando `estado.md` a cada fatia. Paro e pergunto só em dúvida de produto nova ou bloqueio de ambiente. Relatório final curto conforme seção 7 do doc 12.
