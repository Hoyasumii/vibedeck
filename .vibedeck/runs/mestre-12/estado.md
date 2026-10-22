# Estado — prompt mestre 12
Início: 2026-10-22 | base HEAD 0d85034 | branch claude/peaceful-rubin-0mtjcy
Ambiente: Linux x86_64; cargo/rustc 1.97, node 22, python 3.13. Sem swift, graphify, vibedeck.
Plano aprovado: ver roteiro.md (decisões D-*). Subagentes: Sonnet.

## Decisões (2026-10-22, usuário)
D-AMB-1 APP via CI macOS (PR draft) | D-AMB-2 ignorar CLI/MCP vibedeck (gates de regras/workflow pulados)
D-GIT commit por fatia + push | D-EST estado aqui
D1/D2 V2 alvo; revisar regras de UI 047D2216 492100C1 335DA4F8 3901FA3E 34D2EA32 A999B857
D3 onboarding: pasta sem vibedeck.json/Novo projeto; Pular retomável; varre .claude/{agents,commands,skills}, .codex/prompts
D4 Docs: todo .md da raiz → symlink relativo automático; edita origem; quebrado=aviso; colisão=-raiz
D5 nuvem: remover e limpar dados | D6 ícones reuso; só Claude/Codex
D7 macOS universal + Linux musl x86_64/aarch64 | D8 sshd local em container
D9 fronteira processo+JSON | D10 Site só schemas; Releases preparado sem publicar
D11 paridade total de dados | D12 remover Core Swift após paridade | D13 Sonnet
D-MERGE (usuário): ao terminar tudo, abrir PRs e mergear na main resolvendo conflitos (atenção: merge na main dispara deploy do worker)

D14 (usuário): regras que verificavam o Core Swift são reescritas para o Rust (briefing-regras.md)
D15 (usuário): stack/padrões em vibedeck.json atualizados para Rust
D16 (usuário): SSH direto no servidor (MCP via ssh) + reconexão automática com intervalo crescente + estado offline somente leitura (cache da última leitura); sem edição offline nem conflito

## Trilhas
- CORE: todas as áreas + onboarding + consolidação + superfície do app (`mcp --app`, notificações, progresso, cancelamento); 399 testes; contrato MCP ok; paridade aprovada por verificador. Pendências em f04/pendencias.md.
- APP: cliente MCP do Core Rust (Sources/VibeDeckApp/Core), Core/CLI Swift removidos, nuvem fora da UI, V1 removida. NÃO compilado (sem CI). Em andamento: D16 + bugs 48989eac/8a34ae9e.
- SITE: SITE-1 APROVADO (typecheck, validate 10 schemas + 464 dados, 102 rotas ok; verificado pelo coordenador)

## Donos
- CORE: Cargo.*, crates/, schema/, .github/workflows/rust.yml
- APP: Sources/VibeDeckApp/, scripts/make-icon.swift, Package.swift
- SITE: worker/

## Gates/limitações
- graphify, rules_for/submit_rule_check, workflow_run_*: indisponíveis (D-AMB-2)

## Próximo passo
- F01 inventário + APP-1 tokens em paralelo

## PR
- Hoyasumii/vibedeck#11 (draft, CI)
- 2026-10-22 usuário: remover CI/CD por enquanto; recriar ao final. Cópias em ci-desativado/. APP sem compilação até recriar (sem Swift local).
- 2026-10-22 17:11 interrupção do usuário parou 7 agentes; retomados nos mesmos worktrees às 17:47, sem perda.
- Regras: lotes A–D reconciliados com o Rust; faltam as de interface que olhavam ProjectWindow (V1) e refresh de ruleHash das regras D2.
- Retomada em outra sessão: RETOMAR.md.
