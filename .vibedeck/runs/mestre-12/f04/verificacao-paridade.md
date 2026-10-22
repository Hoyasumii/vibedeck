# Verificação de paridade Rust x Swift (CLI + MCP) — mestre-12/f04

Veredito: **APROVADO** (com 2 observações menores, não bloqueantes).

## 1. CLI
- `cargo build --release -p vibedeck`: OK (já compilado).
- Árvore real percorrida recursivamente: 26 grupos/folhas de 1º nível (sem `cloud`, conforme D5) e **136 folhas**. Esperado: 135 (137 Swift - 2 cloud). Diferença: +1 `docs unlink` (adição do Rust, não existia no Swift).
- Nenhum comando/subcomando faltando ou renomeado em relação à árvore do cli.md §1 (reorganize, groups, kits, graph, ai, init, status, stack, patterns, links, claude, docs, review, rules, ideas, agents, commands, skills, workflows, runs, tag, hook, usage, logs, mcp).
- `vibedeck cloud` -> `unrecognized subcommand` (esperado).
- Flags amostradas em ~45 folhas (review add/set/list/remove, rules new/for/test/set-test/check/checks, ideas new/list, agents/commands/skills new/set/next/import, workflows new/set/step/visits/route/flow, runs start/record/stop/questions/list/ask, hook install/stop/status, logs list/crashes, mcp install, usage show, stack badge/search, patterns add, tag, docs new/write, reorganize analyze/apply, ai catalog/usage/context, kits add, init, status, graph export, claude add/list, links add): nomes, atalhos (-C, -a, -s), defaults (note, normal, 24h, warning, 100, 14d, 20, 4000, 50, claude, 25...), `--nenhuma`, `--argument-hint` só em commands, `--reference` só em skills, num_args(1..) em --tags/--rules/--topics/--tools/--component: todos conferem.
- Grupos com subcomando padrão: `ideas|review|rules|docs|stack|patterns|agents|commands|skills|links|claude|workflows|runs|logs --json` sem subcomando funcionam (exit 0, JSON `[\n\n]` com formato Foundation); `hook` -> status JSON; `usage` -> show (exit 1 "Nenhum uso registrado ainda..." igual ao Swift). `groups` não tem default (correto: não está no cli.md).
- Diferença: `--root` aparece também como global no raiz (inofensivo).

## 2. MCP
- `vibedeck mcp` (stdio) em tempdir com `init`: initialize OK (protocol 2025-03-26, capabilities tools/resources listChanged=false, subscribe=false, instructions pt-BR), tools/list = **97** tools; conferidas por nome com mcp.md §4: 0 faltando, 0 sobrando (99 - cloud_check - start_cloud_session).
- resources/list: 5 fixos esperados (project, stack, patterns, logs, logs/crashes) em projeto vazio; resources/read de URI desconhecida -> erro -32602 "URI desconhecida: ..." (igual ao Swift).
- `python3 -I scripts/mcp-contract.py target/release/vibedeck check Tests/Fixtures` -> exit 0 (instructions 2803->978, tools 42434->29099, rules_for 17018->23515 bytes reportados).

## 3. Fluxo ponta a ponta (tempdir; cwd = projeto)
| comando | exit |
|---|---|
| init <dir> --name demo | 0 |
| --version | 0 (imprime `vibedeck 0.1.0`) |
| ideas new "Ideia A" --body corpo --tags x y | 0 |
| ideas list --json | 0 |
| ideas add-rule ideia-a "Regra rascunho" | 0 |
| review add geral "Item 1" ... --rules geral (antes de existir o tópico) | 1 (erro claro "Tópico de regras não encontrado", igual ao Swift) |
| rules new Geral --path 'src/**' | 0 |
| rules add geral "Sem unwrap" / "Doc atualizada" --should | 0 / 0 |
| rules list | 0 |
| rules for src/a.rs --json | 0 (manualRules: 2) |
| rules check --task t --file src/a.rs | 0 (Aprovado, 2 manuais não verificadas) |
| rules check ... --manual --results '[]' | 1 (Check incompleto, lista faltantes) |
| rules checks | 0 |
| review add geral "Item 1" --rules geral | 0 |
| review list | 0 |
| review set <id> --status done (sem check) | 1 (bloqueia: "não pode ser concluído sem passar pelas regras") |
| rules test | 0 ("Nenhuma regra aplicável tem script") |
| docs list / docs list --json (README.md na raiz) | 0; JSON traz `"linked": true`, slug `readme`; espelho `.vibedeck/docs/readme.md -> ../../README.md` (symlink) |
| docs write readme --text "# Novo texto" | 0; README.md = "# Novo texto", continua `-rw-r--r--` arquivo regular; `.vibedeck/docs/readme.md` continua symlink |
| docs cat readme / docs new "Guia X" / docs list | 0 |
| workflows new WF; agents new Ag; workflows step wf ag; workflows show wf | 0 |
| runs start wf --input x; runs list; runs next wf/x | 0 |
| stack list | 0 |
| stack add rust; stack search rust (sem rede) | 1, "Skill Icons indisponível: CONNECT proxy failed ..." (erro claro) |
| patterns catalog tdd; patterns add tdd; patterns list | 0 |
| kits list; groups list ideas; links add; tag idea; ai guide --section 0 | 0 |
| hook install | 0 (.claude/settings.local.json) |
| graph export (sem graphify-out) | 1 ("Grafo: graphify-out/graph.json não encontrado...") |
| logs path; reorganize prompt; status; status --json | 0 |
| mcp install --scope project --provider codex | 0 |
| cloud | erro de parse (comando removido, esperado) |

## Lacunas / observações (não bloqueantes)
1. Versão: `--version` e serverInfo MCP reportam **0.1.0**; Swift era 0.2.0 (cli.md §4: nome vibedeck, versão 0.2.0). Alinhar se a paridade de versão importar (contrato passou mesmo assim).
2. `docs list` em texto não mostra marca de vinculado (só `--json` tem `linked`); se desejado, indicar no texto. Comportamento do Swift original não tinha o conceito.
3. Extra: `docs unlink` (não existia no Swift) — adição, não lacuna.
4. Não exercitados (dependem de binários/rede externos): `reorganize analyze`, `usage show --provider codex`, `mcp install` com claude, `stack add/search/badge` com rede.

Nenhum código foi editado.
