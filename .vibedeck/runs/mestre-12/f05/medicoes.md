# F05 — Medições do binário Rust (2026-10-22)

Ambiente: container Linux x86_64, binário `--release` (gnu), cópia deste projeto (48 tópicos de regras, 324 checks, 44 ideias). Mediana de 10 execuções, processo novo a cada vez.

| Operação | Mediana | Mínimo |
| --- | --- | --- |
| `vibedeck --version` | 4,7 ms | 3,9 ms |
| `status --json` | 16,2 ms | 14,7 ms |
| `ideas list --json` | 14,8 ms | 13,3 ms |
| `rules for <arquivo>` | 12,6 ms | 11,1 ms |
| MCP `initialize` + `tools/list` (processo novo) | 6,6 ms | 5,7 ms |

Tamanho: binário musl estático 3,2 MB (x86_64); gnu release 9,8 MB.
Payload MCP (scripts/mcp-contract.py): instructions 978 (Swift 2803), tools/list 29 099 (Swift 42 434, -32%), rules_for 23 515 (referência Swift antiga 17 018).

Limitações: sem Swift neste ambiente não houve baseline Swift na mesma máquina; as comparações acima usam a baseline gravada em Tests/Fixtures/mcp-budget-baseline.json. O tamanho maior de `rules_for` precisa ser comparado com o Swift atual sobre o mesmo projeto antes de concluir regressão (os dados de regras cresceram desde a baseline). Nenhuma otimização foi feita sem perfil que a justificasse.
