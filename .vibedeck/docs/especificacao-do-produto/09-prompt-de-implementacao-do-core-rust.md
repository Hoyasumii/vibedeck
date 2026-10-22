---
author: ai
---
# 09 — Prompt de implementação do Core Rust

# Prompt de coordenação — Core, CLI e MCP em Rust

## Como usar

Abra uma sessão com acesso ao repositório e ao MCP/CLI do VibeDeck e envie o bloco entre “Início do prompt” e “Fim do prompt”. A execução requer capacidade real de lançar subagentes Claude Sonnet. Este documento prepara a execução; sua criação não iniciou a reescrita, promoveu ideias ou alterou os agentes cadastrados.

Os recursos citados existem no catálogo consultado em 22/10/2026. O fluxo base é `ferramenta-com-revisao-2` (UUID `8CD31CAE-4C51-434F-843B-C8CECE31D412`). Confirme o catálogo no checkout em que executar. Esta publicação leva as especificações; os cadastros locais de stack, padrões e ideias podem estar em outro estado. O documento 08 transcreve os padrões para consulta, mas não prova seu cadastro nem aprovação no checkout de destino.

A autorização desta tarefa foi para commit/push deste material na main. A futura implementação deve seguir sua própria autorização de publicação; o prompt abaixo não transfere automaticamente essa autorização para meses de alterações de código.

---

## Início do prompt

Você é o coordenador da migração do VibeDeck para um novo Core, CLI e servidor MCP em Rust. Execute a migração por entregas verificáveis, usando os recursos do próprio VibeDeck e subagentes de implementação Claude Sonnet. Continue até cumprir o escopo aprovado ou encontrar um bloqueio concreto que dependa do usuário/ambiente. Planejar não equivale a entregar.

### 1. Objetivo e limites confirmados

- Core compartilhado em Rust, com regras de negócio reutilizadas por CLI, MCP e pelo cliente macOS; a interface nativa permanece em SwiftUI.
- MCP por **stdio**, utilizável localmente e por SSH. Não introduza um servidor HTTP ou daemon obrigatório como pressuposto.
- Distribuição por artefatos pré-compilados, com pouca preparação na máquina de destino. Separar requisitos do binário básico daqueles de providers, SSH e verificações que dependem de ferramentas externas.
- Remover a feature de sessões de nuvem; preservar execução local e SSH. APIs dos providers e Cloudflare Workers dos schemas não são essa feature.
- Guiar quem começa um projeto com perguntas de stack e padrões. Detectar skills, agentes e comandos existentes e oferecer cadastro com escolha explícita; não importar/sobrescrever automaticamente.
- Espelhar Markdown da raiz, como README.md, em Docs por link simbólico, preservando a origem. Definir os detalhes pendentes de edição, remoção, links quebrados, permissões e suporte por plataforma antes da implementação afetada.
- Manter compatibilidade dos dados e dos comportamentos aprovados, com exceções deliberadas documentadas. Não traduzir Swift linha por linha nem copiar como requisito definitivo tudo que existe hoje.
- Atualização automática (MUD-004, [doc 10](10-atualizacao-automatica.md)) **fica fora da primeira versão**: não implemente Sparkle, feed, pipeline de release, `self-update` nem UI de atualização. Apenas não tome decisões que impeçam adicioná-la depois.
- Não criar uma UI Windows/Linux, acrescentar OpenCode, trocar providers automaticamente ou converter todos os scripts antes de validar o piloto sem decisão de escopo.

### 2. Fontes e preparação

Leia `.vibedeck/AGENTS.md`, este prompt, os documentos `00`, `01`, `02`, `04`, `05`, `06`, `07` e `08` em `.vibedeck/docs/especificacao-do-produto/`. Abra os documentos de funcionalidades pertinentes a cada fatia. Preserve integralmente as respostas humanas do documento 01. O inventário atual e os cenários candidatos ainda podem ser revisados pelo usuário.

Consulte stack, padrões, regras, revisões abertas e ideias pelo MCP/CLI. Use o grafo por consulta quando existir; leia as fontes relevantes e registre arquivo:linha, testes e comandos. Não use um grafo antigo como prova de comportamento atual.

Registre HEAD, branch, base, estado inicial do worktree e versões das ferramentas. Preserve alterações de terceiros. Prepare checkout isolado quando necessário; não use reset, stash ou limpeza destrutiva para obter um estado conveniente. Não misture commits alheios.

Compare os cadastros vivos com o documento 08. Se faltarem registros, não invente que existem: registre a diferença e proponha a sincronização via CLI/MCP com autoria correta. Não reescreva cadastros humanos nem altere regras ativas apenas para fazer a migração passar.

Localize as ideias pelos UUIDs do documento 00. Se não estiverem nesse checkout, o roteiro documental ainda serve para exploração e planejamento; sinalize a ausência e regularize os registros antes de executar uma operação que dependa deles. Não crie duplicatas nem suponha readiness/dependências satisfeitas. Promoção de ideias em regras exige pedido explícito e os gates próprios.

A regra rascunho `13D1425F-0210-42DD-B667-A24FFDA86743` exigia nuvem e foi revogada pela decisão do usuário: reconcilie o registro antes de promover/implementar a ideia correspondente. Se a ferramenta não permitir a atualização, registre esse bloqueio precisamente. Não promova o requisito antigo.

### 3. Decisões antes do código afetado

Faça um inventário de contratos e uma matriz por funcionalidade: manter, mudar, retirar ou pendente; requisito, origem, interface, dados, teste de aceite, responsável e evidência.

Resolva com o usuário somente decisões de produto que bloqueiem a próxima fatia: sistemas/CPUs da entrega, ambiente SSH, distribuição, fronteira SwiftUI/Rust, destino de recursos e dados, política dos symlinks e exceções à compatibilidade. Apresente uma recomendação com tradeoffs, registre a resposta e prossiga nas tarefas independentes. Ausência de resposta não é aceite.

Escolhas técnicas reversíveis dentro do escopo aprovado podem ser tomadas com justificativa. Exemplos de crates, metas numéricas, cenários candidatos e campos “pendente” não são aprovação. Zod não obriga inserir TypeScript no Core; justifique seu papel ou deixe a decisão pendente.

Consulte documentação oficial atual para SDKs, protocolo MCP e bibliotecas escolhidas. Fixe versões, toolchain e plataformas suportadas de forma reprodutível. Não assuma nomes de APIs nem compatibilidade por memória.

### 4. Recursos do VibeDeck e modelos

Recupere o conteúdo completo pelos slugs, não apenas os resumos:

| Papel | Recurso |
| --- | --- |
| Ciclo por fatia | workflow `ferramenta-com-revisao-2` |
| Planejamento | skill `planejamento-de-ferramenta-2` |
| Implementação | comando `desenvolver-ferramenta-2` |
| Revisão independente | agente `revisor-de-ferramentas-2` |
| Trabalho delimitado de código | agente `implementador` |
| Verificação independente | agente `verificador` |

Use `get_workflow`, `get_skill`, `get_command`, `get_agent` ou os comandos equivalentes do CLI. Confirme referências e limites antes de executar. Não escolha recursos de mesmo título com outro sufixo por acaso.

O workflow `conduzir` e seus comandos pressupõem issue, arquivos e gates específicos; não os invoque com uma issue fictícia. Use o fluxo de ferramenta acima para esta migração.

**Política explícita desta execução:** todos os subagentes de etapas e os implementadores auxiliares usam Claude **Sonnet**. O coordenador mantém o modelo escolhido pelo usuário. Resolva “sonnet” pelo mecanismo disponível e registre o modelo efetivo. Não prometa Sonnet em uma thread Codex nem substitua por Opus, Haiku ou GPT se indisponível. Neste caso, informe a limitação e peça uma sessão/capacidade compatível; não simule delegação.

A execução do workflow deve refletir o provider real. No ambiente Claude usado para estes subagentes, registre `provider: claude`; em operações efetivamente executadas pelo Codex, `provider: codex`. Não rotule uma execução Codex como Claude para contornar o limite. Este prompt solicita Sonnet explicitamente, sem autorizar fallback automático. Não altere globalmente os modelos dos recursos compartilhados; passe a configuração à execução/subagente. Se o runtime não permitir isso, pare esse despacho com explicação.

Adapte as instruções históricas de build Swift dos agentes ao plano aprovado: inclua os checks Rust e mantenha Swift enquanto houver código Swift afetado. A regra vigente de checks automáticos prevalece sobre exemplos antigos de envio manual de resultados. Preserve limites de ferramentas, permissões e proibição de Git nos implementadores.

### 5. Orquestração persistente por fatia

Crie um roteiro mestre versionável em Docs, via CLI/MCP, com fases, contratos, decisões, dependências e matriz de aceite. Artefatos de execução ficam em `$RUN_DIR`, sem misturar evidência temporária, logs e segredos ao material de produto.

Para cada fatia, use entrada estável e concreta: “Core Rust / fase NN / fatia ID / objetivo / critérios de aceite / base”. Inicie ou retome com `workflow_run_start` e provider real; guarde a referência retornada. Não invente o caminho da run. Consulte `ai_guide(section: 13)` e a interface atual antes de usar o CLI.

Ciclo do coordenador:

1. Consulte `workflow_run_next(run)`.
2. Em `run-step`, lance um subagente Sonnet com a instrução de obter `workflow_run_step(run)` e executar a etapa. Passe também objetivo, restrições, decisões confirmadas e os caminhos dos artefatos necessários. A etapa recebe seu prompt completo pelo VibeDeck.
3. Em planejamento, exija plano completo, arquivos sob responsabilidade de cada executor, contratos/interfaces, testes, riscos, rollback e definições de pronto. O comando de implementação só começa com um plano explicitamente validado contra esses critérios pelo coordenador; ambiguidade de produto volta ao usuário. Registre a validação e hash do plano.
4. Na implementação complexa, o agente da etapa coordena executores Sonnet com o prompt `implementador`. Divida por contratos e arquivos, não por quantidade de linhas. Nunca dois escritores no mesmo arquivo. Cargo.toml, Cargo.lock, schemas, registro CLI/MCP e ponte Swift têm um responsável de integração. Dependências são executadas em sequência; só partes sem sobreposição podem rodar em paralelo. Respeite a capacidade de concorrência do ambiente.
5. Cada executor devolve arquivos alterados, testes realmente executados, resultado, divergências e bloqueios. Não faz Git. O coordenador integra as partes antes da verificação.
6. Use um verificador Sonnet independente para executar os critérios e testes. Ele não corrige o código. A etapa de revisão do workflow compara o resultado com o objetivo e emite `APROVADO` ou `AJUSTAR`, com evidências.
7. Registre o veredito real da etapa com `workflow_run_record` e resumo curto. Não fabrique sucesso para avançar. Preserve `PLANEJADO`, `IMPLEMENTADO` e os vereditos esperados pelo recurso.
8. Em `ask`, apresente as perguntas abertas ao usuário e registre respostas com `workflow_run_answer`. Subagentes registram dúvidas com `workflow_run_ask` e retornam `PERGUNTA`; não respondem por conta própria.
9. Em `decide`, avalie a condição com evidência e registre a transição. Em `done`, confira os critérios da fatia; terminar a run não prova concluir toda a migração. Em `stop`, preserve o estado e explique a causa.

O workflow consultado limita a execução a 10 etapas e implementação/revisão a 3 visitas. Releia os limites reais: não os aumente automaticamente nem crie uma run nova para apagar reprovações. Após o limite, registre causa e plano de correção; a retomada deve ser explícita. Um bloqueio de ambiente não vira falha de produto nem aprovação.

Antes de encerrar sessão ou trocar contexto, salve fase/fatia, run, HEAD, arquivos em trabalho, decisões, testes, falhas, checks e próximo passo. Ao retomar, reconcilie esses dados com o disco e o estado da run antes de executar.

### 6. Ordem e entregas

**Fase 01 — Arquitetura e contratos.**
Inventarie a superfície completa de Core, CLI e MCP; argumentos, defaults, JSON, erros, exit codes, schemas, ferramentas, recursos e capabilities. Complete a matriz das 12 áreas do produto. Defina domínio, casos de uso, adaptadores de persistência/processos/providers/SSH e fronteiras dos clientes. Avalie processo/JSON versus FFI para SwiftUI com uma prova pequena e decisão registrada. Padrões do documento 08 devem orientar responsabilidades, não exigir um crate por padrão. Entrega: decisões mínimas, contratos verificáveis, plano de distribuição, fixtures e sequência de fatias.

**Fase 02 — Core mínimo + CLI mínimo + MCP stdio local e SSH.**
Crie uma fatia vertical real com leitura e escrita representativas aprovadas na fase 01. Use o mesmo caso de uso pelo CLI e MCP. Valide negociação, listagem e chamada MCP num cliente real; stdout exclusivo do protocolo, diagnóstico em stderr, erros estruturados, encerramento e cancelamento. Distribua um artefato de teste que funcione sem Swift, Cargo, Python ou UI no destino para as operações básicas. Repita em máquina limpa e SSH com projeto temporário. Registre pré-requisitos reais; não substitua o binário instalado antes dos gates.

**Fase 03 — Piloto de 3 a 5 verificações em Rust.**
Selecione verificações representativas; preserve descoberta/escopo, ambiente, diagnóstico e semântica 0=pass, 77=na, demais=fail. Teste timeout, cancelamento, validade por hash, concorrência e resultados must/should/manual. Compare scripts atuais e runner Rust em fixtures equivalentes. Preserve coexistência/rollback; usar Rust no runner não elimina a dependência de Swift de um teste Swift. Só amplie após a prova.

**Fase 04 — Core, CLI e MCP completos, integração macOS e mudanças de produto.**
Migre as áreas da matriz em fatias verticais: persistência e identidade; documentos/grupos/tags; ideias e dependências; regras/checks/revisões; stack/padrões; agentes/comandos/skills; workflows/runs; providers/chat; SSH; demais recursos mantidos. A ordem interna depende dos contratos, não desta enumeração.
Inclua início guiado, Docs por symlink e retirada das sessões de nuvem. Integre a UI ao Core Rust sem uma segunda implementação das regras de negócio. Atualize instalação, empacotamento, schemas, ajuda e documentação. Remova o Core/CLI/MCP Swift substituído somente após paridade aprovada, transição de dados e rollback verificado. Não deixe stubs, TODOs ou caminhos antigos ocultando ausência de funcionalidades.

**Fase 05 — Desempenho e consolidação.**
Capture baseline antes da substituição e repita amostras comparáveis após ela. Meça startup, operações representativas, volume de arquivos, memória e o que for relevante para a UI. Corrija regressões comprovadas e faça otimizações justificadas por perfil. Não invente metas ou declare ganho sem medição. Confirme que distribuição, manutenção e testes permanecem simples.

### 7. Contratos que precisam de evidência

- Round-trip e migração de JSON/Markdown com IDs, autoria, datas, referências e relações preservados. Campos desconhecidos/vazios, arquivos inválidos, conflitos e escrita atômica seguem política explícita.
- CLI e MCP exercitam os mesmos casos de uso e preservam os contratos mantidos; mudanças aprovadas aparecem na matriz com caminho de transição.
- Symlinks não permitem escapes arbitrários, não apagam a origem ao desvincular e não são substituídos por arquivos comuns ao editar. Testar comportamento real nas plataformas declaradas.
- Regras mantêm globs, escopo, prioridade, scripts e manuais pending; checks históricos não são reescritos. Dependências/readiness de ideias e gates de revisão continuam efetivos.
- Workflows preservam perguntas/respostas, checkpoints, limites e retomada; provider, modelo, effort e permissões não mudam silenciosamente.
- SSH testa execução no host correto, caminhos, desconexão, reconexão e conflitos; falha de conexão não perde trabalho.
- Onboarding permite aceitar/recusar cadastro sem alterações silenciosas. Nuvem deixa de ser oferecida conforme a política de transição, preservando os dados antigos que devam permanecer.
- Um clone/artefato limpo reproduz os resultados com a lista documentada de pré-requisitos; só declare plataformas efetivamente verificadas.

### 8. Validação e fechamento de cada fatia

Execute os testes pertinentes de domínio, integração, contrato CLI/MCP, persistência e migração. Na workspace Rust use formatador, Clippy e testes para os targets/features suportados, com comandos exatos registrados no plano; enquanto o app/legado Swift existir, rode os checks Swift aplicáveis. Teste os fluxos local/SSH e a distribuição nas fases que os entregam. Não transforme compilação cruzada em prova de execução real.

Após modificar código, atualize o grafo com `graphify update .` quando disponível e exigido. Não trate isso como substituto de testes.

Com os arquivos finais, chame `rules_for` e `submit_rule_check` **sem results**. Os scripts executam; as manuais permanecem pendentes. Corrija falhas must e repita. Informe warnings e contagem de manuais. Verificação manual só por pedido ou pelo gate explícito de fechamento de revisão; nesse caso forneça evidência de cada regra exigida. Nunca marque pass por inferência da intenção do código.

Falha de ambiente é bloqueio documentado, não teste aprovado. Se a chamada MCP expirar, confira se o check foi persistido antes de repetir. Não edite checks nem AGENTS.md para contornar o gate. Regra incompatível com a migração precisa ser reconciliada legitimamente, não desativada para passar.

Somente o coordenador faz Git. Adicione arquivos explicitamente, revise o diff, faça commits coesos quando autorizado e mantenha hooks. Não publique nem force-push alterações de implementação sem autorização correspondente. Preserve arquivos e commits de terceiros.

### 9. Definição de conclusão geral

Conclua somente quando a matriz de funcionalidades e contratos do escopo aprovado estiver atendida, os três componentes Rust estiverem integrados, o cliente macOS usar o novo Core, os binários funcionarem nos ambientes acordados, a retirada de nuvem e as mudanças de produto estiverem verificadas, os dados tiverem transição segura e os checks obrigatórios estiverem aprovados.

Relatório final: entrega por fase, commits, plataformas/clientes testados, comandos e resultados, matriz de aceite com evidências, check IDs, warnings/manuais pendentes, decisões e limitações restantes. Uma fase concluída não autoriza declarar todo o Core pronto. Se houver bloqueio, entregue o progresso verificável e o próximo passo concreto.

Comece agora pela preparação, leitura dos cadastros e fase 01. Devolva primeiro o escopo confirmado, as divergências encontradas e as decisões que realmente bloqueiam a próxima fatia; avance em paralelo na exploração independente.

## Fim do prompt
