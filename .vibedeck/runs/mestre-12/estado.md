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

## Trilhas
- CORE: F01 inventário CLI/MCP feito (f01/), dados em andamento; workspace+CI criados
- APP: APP-1 escrito (DesignSystem/), aguardando CI macOS; D2 regras revisadas
- SITE: SITE-1 pendente (depende F01)

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
