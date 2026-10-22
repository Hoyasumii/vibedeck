---
author: ai
---
# 12 — Prompt mestre: Core/CLI/MCP + Site + App macOS

## Como usar

Um único prompt para entregar o novo Core em Rust (CLI + MCP), o Site e o app macOS de uma vez. Ele **não repete** os documentos [09](09-prompt-de-implementacao-do-core-rust.md) (Core/CLI/MCP) e [11](11-prompt-de-implementacao-da-interface.md) (interface): coordena os dois e passa a cada trilha só o que ela precisa. Abra uma sessão Claude com acesso ao repositório, ao MCP/CLI do VibeDeck e com capacidade real de lançar subagentes; envie o bloco entre "Início do prompt" e "Fim do prompt".

"Site" significa o que existe hoje em `worker/` (Cloudflare Worker que serve `schema/v1`). Uma página pública ou de downloads só entra se você confirmar na etapa 0; sem isso, o Site é o worker de schemas atualizado para os contratos do Core Rust.

Criar este documento não inicia a implementação, não promove ideias e não altera agentes, regras ou cadastros.

---

## Início do prompt

Você é o **coordenador** da entrega completa do VibeDeck: Core em Rust com CLI e MCP (trilha **CORE**), Site (trilha **SITE**) e app macOS 26 em SwiftUI (trilha **APP**). Entregue por fatias verificáveis até cumprir o escopo ou encontrar um bloqueio que dependa do usuário. Planejar não é entregar.

### 0. Economia de contexto (vale para você e para todo subagente)

- **Você não lê a especificação inteira.** Leia só: `.vibedeck/AGENTS.md`, `00-indice-e-como-preencher.md`, este documento e as seções "Decisões" dos docs 06, 07 e 11. O resto é lido pela trilha que precisa dele.
- Busque antes de abrir: `graphify query "<pergunta>"` quando `graphify-out/graph.json` existir, `grep`, `ai_catalog`, `ai_guide(section: n)`. Abra trechos, não arquivos inteiros. Não leia `GRAPH_REPORT.md` salvo para revisão ampla de arquitetura.
- **Estado em disco, não na conversa.** Mantenha `$RUN_DIR/estado.md` (≤ 80 linhas): fase/fatia por trilha, runs, HEAD, decisões com data, donos de arquivos, testes, check IDs, bloqueios e próximo passo. Atualize a cada fatia; ao retomar, reconcilie com disco e runs antes de agir.
- **Briefing curto.** Todo despacho usa o modelo da seção 3 (≤ 40 linhas): objetivo, caminhos a ler, restrições, donos de arquivos, critério de pronto, formato de retorno. Passe caminhos e seções, nunca cole documentos.
- **Retorno curto.** Subagente devolve no máximo 30 linhas: arquivos alterados, comandos rodados com resultado, veredito, divergências, bloqueios. Sem dumps de código, diffs ou logs; logs completos vão para `$RUN_DIR/<trilha>/` e o retorno traz o caminho.
- Não releia o que já está em `estado.md`. Não peça a um subagente o que um `grep` ou script resolve em uma chamada.

### 1. Quando delegar

| Situação | Faça |
| --- | --- |
| Tarefa simples, poucas linhas, contexto já carregado | Você mesmo, inline. |
| Tarefa **complexa mas autocontida** (contrato, módulo, tela, teste, script, investigação) que cabe em um briefing | **Novo agente** com contexto limpo e o briefing da seção 3. É o caso padrão. |
| Tarefa que depende de muito do contexto que você já carrega | Fork (herda contexto) ou faça inline; não reconstrua contexto num agente novo. |
| Varredura ampla só para localizar código | Agente de exploração read-only; peça a conclusão, não os arquivos. |
| Verificação de uma entrega | Verificador independente, que não viu a implementação e não corrige código. |

Agentes de trilha (**líderes**) recebem o doc da trilha e coordenam executores; executores recebem uma única fatia. Profundidade máxima: coordenador → líder → executor. Respeite a concorrência do ambiente.

**Modelos:** líderes, executores e verificadores usam Claude **Sonnet**, como exige o doc 09; o coordenador mantém o modelo do usuário. Registre o modelo efetivo. Se Sonnet ou subagentes não estiverem disponíveis, pare o despacho e informe; não troque de modelo/provider nem simule delegação. Execuções de workflow registram `provider: claude`.

### 2. Etapa 0 — preparação e decisões (uma rodada só)

1. Registre HEAD, branch, worktree e versões de toolchain em `estado.md`. Preserve alterações de terceiros; sem reset, stash ou limpeza destrutiva.
2. Consulte `list_stack`, `list_patterns`, revisões abertas e as ideias do índice (UUIDs). Divergências viram nota, não invenção.
3. Monte **numa única mensagem** todas as decisões que bloqueiam o início, cada uma com recomendação e tradeoff:
   - doc 11, "Decisões antes de implementar" (itens 1–6), incluindo as regras ativas de interface em conflito com a V2;
   - doc 06/07: plataformas e CPUs, ambiente SSH, distribuição, política dos symlinks, migração de dados de nuvem;
   - fronteira SwiftUI ↔ Rust (processo/JSON ou FFI) — pode ficar para a prova da fase 01 do CORE;
   - escopo do Site: só schemas (padrão) ou também página pública/downloads.
4. Prossiga no que não depende das respostas (inventário de contratos, tokens e componentes). Ausência de resposta não é aceite; nada que dependa dela é implementado.

### 3. Modelo de briefing

```text
Papel: <líder CORE | líder SITE | líder APP | executor | verificador> — modelo Sonnet.
Objetivo: <uma frase>. Fatia: <trilha/fase/ID>.
Leia: <caminhos e seções exatos>. Não leia o resto da especificação.
Decisões confirmadas: <IDs/linhas do estado.md>.
Você é dono de: <arquivos/diretórios>. Não escreva fora disso. Sem Git.
Restrições: <limites do doc da trilha que se aplicam>.
Pronto quando: <critérios verificáveis + comandos>.
Para dúvida de produto: workflow_run_ask e retorne PERGUNTA; não decida sozinho.
Retorno (≤ 30 linhas): arquivos, comandos e resultados, veredito, divergências, bloqueios, caminho dos logs.
```

### 4. Trilhas

**CORE — Core, CLI e MCP em Rust.** Líder segue o doc 09 (seções 1–9) como fonte: fases 01 a 05, workflow `ferramenta-com-revisao-2`, recursos `planejamento-de-ferramenta-2`, `desenvolver-ferramenta-2`, `revisor-de-ferramentas-2`, `implementador`, `verificador`, limites de etapas/visitas sem aumentá-los. Dono: workspace Rust, `Cargo.*`, `schema/` (fonte dos contratos), registro CLI/MCP.

**APP — interface macOS 26.** Líder segue o prompt do doc 11, com as decisões da etapa 0 já respondidas. Dono: `Sources/VibeDeckApp/`, `scripts/make-icon.swift`. Diferença em relação ao doc 11: o app passa a consumir o **Core Rust** pela fronteira decidida na fase 01 do CORE; a frase "preserve o comportamento do Core" significa preservar os contratos aprovados, não o Core Swift.

**SITE — worker de schemas (e página, se aprovada).** Dono: `worker/`. Consome `schema/v1` produzido pelo CORE; não edita schemas. Valide com `npm run typecheck` e `wrangler dev` (rotas `/`, `/v1`, cada schema, CORS, 405). Deploy só com autorização explícita.

### 5. Ordem e dependências

```text
Etapa 0 (decisões)
 ├─ CORE fase 01: contratos + prova da fronteira Swift↔Rust ──┐
 ├─ APP: DesignTokens.swift + componentes (independe do Core)  │
 │                                                             ▼
 ├─ CORE fases 02–03: Core/CLI/MCP mínimo, SSH, piloto de checks
 ├─ SITE: schemas v1 gerados/validados contra os contratos da fase 01
 ├─ APP: janela V2 e telas (doc 11, item 3), ligadas ao Core Rust conforme cada área fica pronta
 └─ CORE fase 04 (paridade) → APP remove UI antiga e nuvem → CORE fase 05 (desempenho)
```

- Uma trilha só começa o que depende de outra quando o contrato estiver aprovado em `estado.md`.
- Nunca dois escritores no mesmo arquivo. Arquivos de integração (`Cargo.toml`, `Cargo.lock`, `Package.swift`, `schema/`, ponte Swift, registro CLI/MCP) têm um único dono declarado.
- Mudança de contrato depois de aprovada volta ao CORE e é comunicada às outras trilhas por nota em `estado.md`.

### 6. Gates por fatia (não dispensáveis)

1. Testes da trilha: Rust (`cargo fmt --check`, `cargo clippy`, `cargo test` nos targets suportados), Swift (`swift test` enquanto houver Swift), Site (`npm run typecheck`).
2. Verificador independente executa os critérios e devolve `APROVADO` ou `AJUSTAR` com evidência; `workflow_run_record` registra o veredito real.
3. `graphify update .` após alterar código, quando disponível.
4. `rules_for` com os arquivos alterados e `submit_rule_check` sem `results`. `passed=false` → corrigir e repetir. Informe warnings e quantas manuais ficaram pendentes. Manuais só quando o usuário pedir.
5. Falha de ambiente é bloqueio documentado, não aprovação. Não edite checks, `AGENTS.md` ou regras para passar.

Somente o coordenador faz Git: arquivos adicionados explicitamente, commits coesos por fatia quando autorizados, sem force-push nem publicação sem autorização.

### 7. Conclusão

Concluído quando: CORE cumpre a definição do doc 09 seção 9; APP cumpre a conclusão do doc 11 e usa o Core Rust; SITE serve os schemas atuais com typecheck e testes de rota aprovados; checks de todas as fatias com `passed=true`.

Relatório final (curto): entregas por trilha, commits, plataformas testadas, comandos e resultados, check IDs, warnings, manuais pendentes, decisões e limitações. Se parar antes, entregue o progresso verificável, o estado em `estado.md` e o próximo passo concreto.

Comece pela etapa 0 e devolva primeiro a mensagem única de decisões.

## Fim do prompt
