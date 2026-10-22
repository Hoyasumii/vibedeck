# F04 — briefing comum dos executores de área (Sonnet)

## Objetivo
Portar uma área do VibeDeck de Swift para Rust com **paridade**: mesmos comandos CLI (args, defaults, saída texto e `--json`, exit codes), mesmas tools MCP (nome, inputSchema, texto do resultado, erros `isError`) e mesmos efeitos em disco. CLI e MCP chamam a mesma função do core.

## Leia (só isto + o código Swift da sua área)
- `.vibedeck/runs/mestre-12/f01/arquitetura.md`
- Sua seção em `f01/cli.md` (§2.x) e em `f01/mcp.md` (§4.x); `f01/dados.md` §2 e a seção do seu tipo.
- Fonte de verdade: os arquivos Swift da área em `Sources/VibeDeckCore/`, `Sources/vibedeck/CLI.swift` (trechos da área) e `Sources/vibedeck/MCPServer.swift` (trechos da área). Testes Swift da área em `Tests/VibeDeckCoreTests/` mostram o comportamento esperado — porte os casos relevantes.

## Já existe (use, não reescreva)
- Core: `vibedeck_core::{Store, Record, json, time, slug, paths, model::*, Error}`. Store genérico: `list/find/load/save/create/delete/new_slug` + wrappers por tipo; `save_check`, `runs`, `save_run`.
- MCP: `crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text}`, `crate::mcp::args::Args` (`str/req/list/int/int_strict/bool/severity/provider`), `crate::mcp::schema::{schema, prop}`. `ctx.store()?` abre o projeto.
- CLI: `crate::cli::{CliError, Context, output::print_json}`; `ctx.store()?`, `ctx.root()?`. Grupos com subcomando padrão: veja `McpArgs` em `cli/mod.rs` (`args_conflicts_with_subcommands` + `Option<Sub>`).

## Você é dono de (somente)
- `crates/vibedeck-core/src/<area>.rs` (pode virar `<area>/mod.rs` + submódulos)
- `crates/vibedeck/src/mcp/tools/<area>.rs` → `pub fn tools() -> Vec<Tool>`
- `crates/vibedeck/src/cli/<area>.rs` → `pub enum Command` (variantes de **primeiro nível**, ex. `Ideas(IdeasArgs)`) + `pub fn run(command, &Context)`
- Testes em `crates/vibedeck-core/tests/<area>_*.rs` e `crates/vibedeck/tests/<area>_*.rs`
Não edite: `lib.rs`, `cli/mod.rs`, `mcp/tools/mod.rs`, `model/*`, `store.rs`, `json.rs`, `Cargo.toml`/`Cargo.lock`, nada fora de `crates/`. Precisa de campo/método em modelo/store ou de crate nova? Implemente localmente no seu módulo (`impl` em trait de extensão) ou relate no retorno como PEDIDO-INTEGRAÇÃO. Crates já disponíveis no core: globset, regex, sha2, libc, walkdir, ureq (rustls+json), chrono, uuid, unicode-normalization, thiserror, serde_json.

## Regras
- Decisões: D5 nuvem removida (não porte nada de nuvem); D4 Docs vinculados por symlink; D11 paridade de dados. Providers só claude/codex.
- Sem stubs/TODO escondendo falta de funcionalidade: se algo da área ficar de fora, liste no retorno.
- Mensagens ao usuário em PT como no Swift. Ordenações e formatos idênticos.
- Testes: unitários no core + integração do binário (`std::process` com `CARGO_BIN_EXE_vibedeck`, projeto temporário com `tempfile`) cobrindo CLI e MCP da área.
- Sem Git. Não rode `graphify`.
- Pronto quando: `cargo fmt --all --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` passam no seu worktree.

## Retorno (≤ 30 linhas)
Comandos CLI e tools MCP portados (contagem e lista curta), o que ficou de fora e por quê, divergências do Swift, PEDIDOS-INTEGRAÇÃO, comandos rodados com resultado.
