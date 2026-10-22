# Pendências encontradas na reconciliação de regras (para despachar após as tools do app)

## Core Rust
- 48331E51: CLI e MCP não gravam log (`cli.command_completed`, `mcp.tool_called`, `rules.script_finished`); `logs::configure/info` nunca chamados.
- 31465510: `store::write_atomic` não loga `store.file_written`.
- `vibedeck init` não grava AGENTS.md/guide.md (usar `project::init_with` + `ai::guide::write_agents_guide`).
- policy triplicada (`ai/policy_instructions.txt`, `workflows/policy.txt`, `assets/kits/policy.txt`) → uma fonte.
- `VIBEDECK_ACTION` não propagado pelo runner de regras.
- `context::recovery()`/`INCOMPLETE` sem uso no Rust (recuperação só no app) — confirmar com Swift antigo.
- `codex_install` escopo project grava caminhos absolutos — conferir paridade com o Swift.
- 7d9e4052 reiniciar execução; 1a4ef162 ideias órfãs (enviados ao agente das tools do app).
- scripts/test-ai-efficiency.sh ainda usa Swift.

## App
- 9EDE76DF: 5 `Button` crus no DesignSystem V2 (usar o botão com log do app).
- BE4A2B46: filtro de escrita própria (`lastWritten`) sumiu: escritas do app serão logadas como externas.
- 48989eac, 8a34ae9e, D16: com o executor do app.
- Regras de interface V1 (ProjectWindow) a reconciliar com a V2; refresh de ruleHash das regras D2.
