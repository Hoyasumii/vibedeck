# Prompt de retomada — prompt mestre 12

Cole o bloco abaixo numa sessão nova do Claude Code com acesso ao repositório `Hoyasumii/vibedeck`.

---

Você é o **coordenador** da entrega do prompt mestre 12 do VibeDeck (Core/CLI/MCP em Rust + Site + app macOS V2). O trabalho já está bem avançado; retome sem refazer nada.

1. Faça checkout do branch `claude/peaceful-rubin-0mtjcy` (PR draft Hoyasumii/vibedeck#11) e trabalhe só nele. Commit por fatia com push no mesmo branch.
2. Leia, nesta ordem e só isto: `.vibedeck/runs/mestre-12/estado.md` (decisões D-*, D1–D16, situação por trilha), `.vibedeck/runs/mestre-12/roteiro.md` (plano aprovado), `.vibedeck/runs/mestre-12/f04/pendencias.md` (o que falta), `.vibedeck/runs/mestre-12/app/notas-app.md` e `.vibedeck/runs/mestre-12/app/pedidos-core.md`. O prompt mestre original está em `.vibedeck/docs/especificacao-do-produto/12-prompt-mestre-core-interface-site.md`; não releia a especificação inteira.
3. Regras de execução que o usuário definiu:
   - Ignorar o CLI/MCP `vibedeck` instalado para gates de regras (D-AMB-2); use o binário Rust do repo (`cargo build --release -p vibedeck`) e os scripts de regras quando precisar.
   - O CI/CD foi removido a pedido do usuário; as cópias estão em `.vibedeck/runs/mestre-12/ci-desativado/`. **Só recrie o CI no final**, quando tudo estiver pronto (Rust + Swift + worker), e então corrija o que falhar.
   - No fim: abrir/atualizar os PRs e **mergear na main**, resolvendo conflitos. Atenção: push na main dispara deploy do worker de schemas.
   - Subagentes Claude Sonnet para executar; coordenador integra, verifica (fmt, clippy, cargo test, `python3 -I scripts/mcp-contract.py target/release/vibedeck check Tests/Fixtures`, `cd worker && npm run validate && npm run test`) e faz o Git. Paralelismo à vontade.
   - Não há Swift no container Linux: código Swift do app só é validado quando o CI macOS voltar.
4. Estado resumido (confira em estado.md): SITE pronto; Core Rust com todas as áreas, contrato MCP ok, superfície do app em `vibedeck mcp --app`; app migrado para cliente MCP do Core Rust (Core/CLI Swift removidos), não compilado; regras reconciliadas com o Rust exceto as de interface que olhavam a janela V1.
5. Próximos passos: (a) concluir/integrar as correções do app (D16 SSH direto + reconexão + offline só leitura, bugs 48989eac e 8a34ae9e, CoreStore usando os nomes exatos de pedidos-core.md); (b) pendências do Core em pendencias.md (logs, init grava guia, policy única, VIBEDECK_ACTION, etc.); (c) reconciliar as regras de interface com a V2 e atualizar ruleHash das regras D2; (d) acabamento das telas V2 (pranchas 13–38), telas de início guiado (31–34) e Docs vinculados (35–36); (e) recriar o CI, compilar e corrigir o Swift; (f) PR e merge na main.

Comece lendo estado.md e reporte em poucas linhas o que vai fazer primeiro.

---
