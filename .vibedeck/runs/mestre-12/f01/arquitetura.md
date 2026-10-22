# CORE F01 — Arquitetura, contratos e sequência (decisões registradas 2026-10-22)

Fontes: `cli.md` (137 comandos), `mcp.md` (99 tools no código, 85 no contrato), `dados.md` (formato em disco).

## A1. Workspace
- `crates/vibedeck-core` (lib, síncrona, sem tokio): domínio + persistência + casos de uso. Único lugar com regra de negócio.
- `crates/vibedeck` (bin `vibedeck`): adaptadores finos — `cli/` (clap derive) e `mcp/` (JSON-RPC stdio). CLI e MCP chamam as mesmas funções do core.
- Sem crate por padrão de projeto; módulos por área dentro do core.

## A2. Módulos do core (donos por fatia)
`json` (emissor VDJSON byte a byte, dados.md §2/Apêndice A) · `time` (ISO-8601 UTC sem fração; ms em RuleCheck) · `slug` (Slug.make, uniqueSlug, resolveSlug) · `paths` (validatedRecordURL/containedURL, symlinks de Docs D4) · `store` (raiz, leitura tolerante, escrita atômica temp+rename, não regravar sem mudança) · `model/*` (um arquivo por schema v1) · áreas: `project`, `ideas`, `reviews`, `rules` (rules_for, runner, checks), `docs`, `links`, `groups`, `tags`, `stack`, `patterns`, `agents`, `commands`, `skills`, `kits`, `workflows`, `runs`, `ai` (claude/codex), `usage`, `graph`, `hook`, `logs`, `guide` (AGENTS.md/guide.md embutidos, sem nuvem), `onboarding` (D3), `reorganize`.

## A3. Fronteira SwiftUI ↔ Rust (D9)
O app é **cliente MCP** do mesmo binário: inicia `vibedeck mcp -C <raiz>` (local) ou `ssh <host> vibedeck mcp -C <raiz>` (SSH) e chama tools via JSON-RPC por stdio. Resultados de tools já são JSON em texto. Um único contrato para IA, CLI e app; nenhuma ABI/FFI. Prova: `CoreClient.swift` mínimo chamando `get_project` (validado na CI macOS). Necessidades só do app (eventos de arquivo) entram depois como notificações MCP, se medidas como necessárias.

## A4. Políticas de dados (D11 + riscos de dados.md §8)
- Escrita tipada segue o Swift: chaves desconhecidas são descartadas ao regravar um registro alterado; arquivo não alterado nunca é regravado.
- Normalizações do Swift na regravação (author ausente, reviewKinds vazio, UUID maiúsculo, datas sem fração) são reproduzidas.
- `id` ausente em tópico: gera UUID ao gravar (não a cada leitura em memória — gerar estável por sessão é aceitável).
- Slug: NFKD + remoção de diacríticos + minúsculas + `[^a-z0-9]+`→`-`; testes com fixtures das pastas reais.
- Escrita atômica: temp no mesmo diretório + rename; em Docs vinculados, resolve o alvo do symlink antes (o link continua link).
- Checks históricos nunca reescritos.
- Nuvem (D5): `codexCloudEnvironment` removido do Project na regravação; seções de nuvem saem do guia embutido; tools/comandos de nuvem removidos. Doc livre `docs/sessoes-na-nuvem-e-limites-de-uso.md` é conteúdo humano: mantido (não é dado da feature).

## A5. Contratos verificáveis
- MCP: `Tests/Fixtures/mcp-contract.json` regenerado sem `start_cloud_session`/`cloud_check` (exceção D5) + as 14 tools extras; `scripts/mcp-contract.py <rust-bin> check Tests/Fixtures` no CI Rust.
- Dados: teste de round-trip lendo e reemitindo todo `.vibedeck/**/*.json` deste repo (464/466 byte a byte, as 2 exceções de `tests/` excluídas).
- CLI: testes de saída `--json` e exit codes por comando portado (assert_cmd), usando fixtures temporárias.

## A6. DEC-004 — fatia mínima (F02)
Leitura: `get_project`, `list_ideas`, `rules_for`. Escrita: `add_review_item`. Mesmo caso de uso no CLI (`vibedeck project --json`, `ideas list --json`, `rules for`, `review add`) e no MCP.

## A7. DEC-005 — piloto (F03)
Runner Rust (dados.md §5: `$SHELL -lc`, env VIBEDECK_*, timeout 120s→124, 0/77/outro, saída 4000, paralelismo com trava por ferramenta) com 4 regras: `geral/9F92A765`, `worker-e-schemas/0A89A5BC`, `core-e-formato-de-dados/57ADA275`, `core-e-formato-de-dados/DFE3361B` (should). Comparar vereditos com os registrados pelo Swift.

## A8. Distribuição (D7/D10)
Artefatos do workflow `rust.yml`: musl x86_64/aarch64, macOS universal. Pré-requisito no destino: nenhum (binário estático) para operações locais; `claude`/`codex`/`git` só para os comandos que os chamam.

## A9. Sequência
F02 fundação+fatia mínima → F03 runner/piloto → F04 por áreas em paralelo (donos de módulos disjuntos; `lib.rs`, `Cargo.toml`, registro CLI/MCP têm dono único = integrador) → APP-2 ligado área a área → remoção Swift → F05.
