# VibeDeck

<!-- vibedeck:stack:start -->
[![My Skills](https://skill-icons.alanreisanjo.workers.dev/icons?i=swift,apple,workers,ts,rust,mcp,zod)](https://skill-icons.alanreisanjo.workers.dev)
<!-- vibedeck:stack:end -->

App macOS nativo (SwiftUI + Liquid Glass) para gerenciar projetos feitos com vibe coding:
links, docs Markdown, **pontos de revisão** ("inativar esse botão", "isso não precisa aparecer agora")
agrupados por tema, **regras** que a IA precisa cumprir antes de dar uma tarefa como concluída e **ideias** futuras. Tudo fica em arquivos dentro do próprio repositório, para a IA ler e escrever também.

## Arquitetura

- **Core, CLI e MCP em Rust**: `crates/vibedeck-core` (biblioteca) e `crates/vibedeck` (binário `vibedeck`, que traz o CLI e o servidor MCP). Compilam em Linux e macOS.
- **App macOS 26 em SwiftUI** (`Sources/VibeDeckApp`): não tem Core próprio, fala com o binário via MCP (`vibedeck mcp --app`), localmente ou por SSH.
- **Worker** (`worker/`): serve apenas os schemas JSON (`schema/v1/`).

## Formato no seu projeto

```
<repo>/
  vibedeck.json              # declara o projeto (nome, links, coleção Claude, stack, padrões, reviewKinds)
  .vibedeck/
    AGENTS.md                # guia inicial compacto para IA (gerado)
    guide.md                 # referência completa, consultada por seção (gerada)
    docs/<slug>.md           # ou symlink para um .md da raiz do repositório (Docs vinculados)
    reviews/<slug>.json      # um grupo/tema por arquivo
    rules/<slug>.json        # um tópico de regras por arquivo (paths = globs de escopo)
    ideas/<slug>.json        # uma ideia por arquivo, com regras rascunho e globs sugeridos
    agents/<slug>.json       # um agente por arquivo: nome, modelo, prompt e próximos passos
    commands/<slug>.json     # um comando por arquivo: prompt com $ARGUMENTS, argumentos e próximos passos
    skills/<slug>.json       # uma skill por arquivo: descrição (quando usar), instruções e próximos passos
    workflows/<slug>.json    # um workflow por arquivo: etapas (agentes, comandos, skills) e transições condicionais
    runs/<workflow>/<execução>/  # execuções de workflows: run.json (estado) + o que as etapas gravam
    tests/<tópico>/<regra>.sh  # scripts gerados a partir das regras ("Gerar testes")
    checks/*.json            # verificações de regras registradas pelos agentes
    attachments/             # arquivos anexados a docs e ideias (arrastar, colar ou "Anexar")
```

## Visualizador de Links

No painel **Links**, dar duplo clique ou escolher **Abrir** no menu de contexto mostra a página
num visualizador interno ao lado da tabela. **Fechar** esconde o painel e devolve a largura à tabela.
O visualizador aceita apenas HTTP/HTTPS, permite os recursos e redirecionamentos da página e abre
links para outras páginas no navegador padrão. **Abrir no navegador** continua disponível no menu
e no painel. Não há barra de endereço ou histórico; cookies e dados de navegação são temporários.
Abrir e fechar o painel não altera arquivos do projeto nem cria passos de undo.

## Coleção do Claude

A coleção reúne artefatos e docs escolhidos pelo usuário em cada projeto, no campo `claude` do
`vibedeck.json`. A sidebar mostra **Claude** e o contador quando há pelo menos um item; após remover o último,
a seção fica oculta. A coleção não depende de ter um provedor de IA instalado.

Na tela **Links**, o botão **Adicionar do Claude** permite adicionar o primeiro item mesmo com a sidebar
oculta. Colar uma URL do Claude nessa tela também abre o formulário. **Adicionar do Claude** abre um formulário com URL, tipo, título e tags. Só são aceitas URLs do `claude.ai`.
O título começa com o último trecho da URL e pode ser editado; o usuário escolhe **Artefato** ou **Doc**,
pois a URL não distingue os tipos. Colar um link (⌘V) abre o formulário e aguarda a confirmação.
A tabela mostra tipo, título, data e tags, com busca (também por `#tag`) e filtro Todos / Artefatos / Docs.
Duplo clique abre no navegador. Editar ou remover registra undo; remover tira apenas da coleção local.
Não há importação automática nem chamadas à API do Claude.

```sh
vibedeck claude list --json
vibedeck claude list --kind artifact --json
vibedeck claude add https://claude.ai/public/artifacts/<id> --kind doc --title "Meu doc" --tags referência
vibedeck claude remove <id-ou-prefixo>
```

MCP: `list_claude_items` (filtro opcional `kind`) e `add_claude_item` (`url`, `kind`, `title`, `tags`).
O tipo é obrigatório na adição; tags seguem os mesmos formatos das demais ferramentas do MCP.

## Stack

A **Stack** é o primeiro item da sidebar e a aba que abre junto com o projeto quando não está vazia. Ela reúne as
tecnologias de destaque, para quem chega ao projeto e para a IA, que consulta a stack antes de implementar algo.
O botão **+** abre um seletor com o catálogo do [Skill Icons](https://skill-icons.alanreisanjo.workers.dev), que pode
ser filtrado por nome, alias ou categoria. O catálogo e os ícones renderizados vêm do servidor MCP do Skill Icons e
ficam em cache em `~/Library/Caches/VibeDeck/skill-icons`. Cada tecnologia aceita uma **nota de uso**
(ex.: "Swift 6, strict concurrency"), que a IA recebe junto com a stack. Para reordenar, arraste os cartões.

A stack fica em `vibedeck.json` (`stack`). Cada mudança regrava o badge entre
os comentários `vibedeck:stack:start` e `vibedeck:stack:end` no `README.md`, cada um sozinho na linha. Quando o bloco não existe, ele é
inserido logo abaixo do primeiro título.

```sh
vibedeck stack                      # lista (--json para a IA)
vibedeck stack search postgres      # procura ids no catálogo
vibedeck stack add swift k8s "Next.js" --note "..."   # aceita ids, nomes e aliases
vibedeck stack remove k8s
vibedeck stack note swift "Swift 6, strict concurrency"
vibedeck stack move swift 0
vibedeck stack badge [--sync]       # Markdown do badge; --sync regrava o bloco no README
```

No MCP, a stack tem as tools `list_stack`, `search_stack_icons`, `add_stack` (author=ai), `remove_stack`,
`update_stack` e o resource `vibedeck://stack`.

## Padrões de projeto

**Padrões** (logo abaixo da Stack na sidebar) diz como o código deve ser escrito, para a IA ser consistente e não
gerar código espaguete: TDD, SOLID, injeção de dependência, núcleo funcional, Clean Code, arquitetura hexagonal,
Clean Architecture, camadas, MVVM, MVC, DDD, CQRS, Event Sourcing e Repository vêm prontos no catálogo, com regras
em pt-BR. O catálogo tem 32 padrões, incluindo desenvolvimento orientado a comportamento, design por contrato,
monólito modular, arquitetura orientada a eventos, objeto de valor, serviço de domínio, composição e representante;
dá para criar padrões próprios (nome, resumo e uma regra por linha). Cada padrão aceita uma nota
("hexagonal só no Core") e um escopo em globs (vazio = projeto inteiro).

Os padrões ficam em `vibedeck.json` (`patterns`), e cada um cria um tópico de regras `.vibedeck/rules/padrao-<nome>.json`
(com `sourcePattern`): as regras chegam à IA pelo `rules_for` e são cobradas no check e no hook `Stop`, como qualquer
outra. Remover o padrão apaga o tópico; apagar o tópico retira o padrão.

```sh
vibedeck patterns                   # lista (--json para a IA)
vibedeck patterns catalog [texto]   # catálogo embutido
vibedeck patterns add tdd hexagonal --path 'crates/vibedeck-core/**' --note "..."
vibedeck patterns add --custom "Feature folders" --rule "Uma pasta por feature"
vibedeck patterns note tdd "cargo test"
vibedeck patterns paths hexagonal 'crates/vibedeck-core/**'
vibedeck patterns remove tdd
```

No MCP: `list_patterns`, `pattern_catalog`, `add_pattern` (author=ai), `remove_pattern`, `update_pattern` e o
resource `vibedeck://patterns`.

Stack e padrões chegam às IAs por consulta, com as notas de uso, sem uma cópia fixa no prompt.
O guia `.vibedeck/AGENTS.md` e a política compartilhada pelos fluxos de Claude/Codex orientam essa leitura
antes de implementar. Os canais têm estas diferenças:

| Canal | Contexto disponível |
| --- | --- |
| MCP `list_stack` / `vibedeck://stack` | Tecnologias e notas; a ferramenta também retorna o badge. |
| CLI `vibedeck stack --json` | Tecnologias e notas do manifesto. |
| MCP `list_patterns` / `vibedeck://patterns` | Padrões, notas, tópico vinculado, globs e regras. |
| CLI `vibedeck patterns --json` | Registros do manifesto, incluindo notas e referência `topic`; consulte também `vibedeck rules for <arquivos> --json`. |
| Arquivos, sem MCP/CLI | Leia `stack` e `patterns` em `vibedeck.json`, os tópicos referidos por `topic` e os demais tópicos aplicáveis em `.vibedeck/rules/`. |

Nos tópicos, `paths` vazio vale para toda tarefa; com globs, vale quando algum arquivo da tarefa casa.
Use `rules_for` para os arquivos e o item de revisão, quando houver, e releia o contexto após alterações.
O badge do README não contém notas nem regras. `patterns` ausente ou vazio significa nenhum padrão
cadastrado; as outras regras continuam valendo. A consulta não garante que a IA siga as orientações:
os checks continuam obrigatórios. Chamadas sem MCP usam CLI ou leitura dos arquivos conforme as permissões;
no Codex, scripts de regras rodam pelo MCP do VibeDeck, fora do terminal do agente.

## Regras e ideias

- **Tópico de regras**: lista de comportamentos (`must` bloqueia, `should` só avisa). Sem `paths`, vale
  para toda tarefa; com globs (`Sources/App/**`, `*.tsx`), vale quando um arquivo alterado casa.
- **Fluxo do agente** (exigido pelas instruções do MCP e pelo `AGENTS.md`): `rules_for` com os arquivos
  alterados → `submit_rule_check` roda scripts; manuais ficam pendentes. Use `include_manual` / `verify_manual`
  (CLI: `--manual`) quando a verificação manual for solicitada, com `pass`/`fail`/`na` e evidência. O envio roda
  os scripts automaticamente. Só conclui com `passed=true`; manuais pendentes são informadas.
- **Testes de regras**: "Gerar testes" (barra do tópico) pede ao provedor selecionado, no chat, para transformar cada regra
  num script em `.vibedeck/tests/<tópico>/<regra>.sh` — ou marcá-la como **manual** quando não dá para testar
  objetivamente. Daí em diante o check roda o script (na raiz, com `$VIBEDECK_FILES` = arquivos alterados):
  exit `0` cumpre, `77` não se aplica, outro código viola — a IA não decide essas regras. Editar o texto ou os
  detalhes de uma regra deixa o teste **desatualizado** (volta a ser manual, com aviso) até "Atualizar testes".
  "Rodar testes" executa os scripts do tópico sem gravar check.
  Na lista de Regras, "Gerar verificações" faz isso para todos os tópicos de uma vez, em segundo plano
  (um `claude -p` por tópico, até 3 em paralelo, registrando pelo CLI): só as que faltam, só as desatualizadas
  ou todas. "Rodar verificações" executa os scripts de todos os tópicos.
- **Executar regras no app:** disponível na lista de regras e em cada tópico. O modo sem IA roda
  somente os scripts; o modo com IA roda os scripts primeiro e verifica as regras restantes com o
  provedor selecionado, disponível apenas quando instalado. O painel mostra progresso, resultados,
  duração e estimativa baseada no histórico local da máquina. Falhas de IA ou regras alteradas durante
  a execução impedem salvar um check incompleto; uma verificação completa fica no histórico, mesmo
  quando contém regras reprovadas. Os scripts não são executados novamente ao salvar.
- **Scripts em paralelo:** os scripts de regras rodam vários ao mesmo tempo, no app, no CLI (`rules check`,
  `rules test`) e no MCP (`submit_rule_check`), com a mesma execução do Core. O limite padrão é o número de
  núcleos da máquina; no app, ele é ajustado em **Configurações** (⌘,) → "Scripts ao mesmo tempo" (de 1 ao
  número de núcleos, guardado só nesta máquina, nunca no projeto). O CLI e o MCP sempre usam o padrão. Scripts
  que chamam a mesma ferramenta de build (swift/xcodebuild, npm/npx/yarn/pnpm, cargo, go, gradle, mvn, dotnet,
  composer, make) rodam um por vez, porque dividem diretórios de build e travas; a detecção lê o arquivo do
  script em `.vibedeck/tests` (e os `source` da mesma pasta). Os resultados saem na ordem das regras. No app,
  **Cancelar** encerra os scripts em andamento e não inicia os da fila; uma regra `must` reprovada também
  interrompe a fila. Execução cancelada ou interrompida não chama a IA nem grava check. O check do CLI/MCP
  roda todos os scripts, mesmo após uma falha `must`, para responder toda regra.
- Item de revisão ligado a regras (campo `rules` ou `target.file` casando um tópico) não vai para
  `done` via CLI/MCP sem check aprovado para o item (`vibedeck review set --force` para humanos).
- **Hook Stop** (`vibedeck hook install`, ou `--scope project` para versionar em `.claude/settings.json`;
  no Codex, `vibedeck hook install --agent codex`, que grava `.codex/hooks.json` e precisa ser aprovado com
  `/hooks` no Codex): o agente não encerra a resposta enquanto um arquivo alterado na sessão (git, desde o início do
  transcript, ou do `SessionStart` no Codex) tiver regras aplicáveis sem um check aprovado, registrado depois da alteração, cobrindo todos
  os tópicos dele. Depois de 3 bloqueios seguidos (`--max-blocks`) ele libera e avisa você, para não
  prender o agente num laço. `vibedeck hook` mostra onde está ligado e o que bloquearia agora.
- **Descubra** (no painel do item de revisão, com Claude ou Codex instalado): a IA explora em modo
  somente leitura, sem MCP, e propõe o **Onde** (arquivo, rota, componente, seletor) e tópicos de **Regras**,
  cada um com a justificativa. Nada muda até você aceitar: arquivos inexistentes e tópicos desconhecidos são
  descartados, trocar um campo já preenchido começa desmarcado, tópicos só são adicionados e o aceite é um
  único ⌘Z.
- **Resolver** (só no app, sem CLI nem MCP; botão em cada item aberto e **Resolver grupo** no cabeçalho, com
  Claude ou Codex instalado): fluxo **pergunta → plano → aceite → execução → check**. Primeiro a IA lê o código
  (Read/Grep/Glob; no Codex sem escrita) e devolve, em JSON validado, perguntas e um plano; você responde na tela
  e aceita o plano. Sem aceite nenhum arquivo nem status muda. Depois do aceite a IA pode escrever no projeto
  aberto, um item por vez; cada item roda seu próprio check e só vai a `done` com `ensureVerified` aprovado
  (um único ⌘Z desfaz). No grupo entram só itens `open` e `in_progress`; uma falha não impede os seguintes nem
  reverte os concluídos. Resolver nunca apaga nem marca `wontfix`: se não conseguir, o item fica como estava e
  você vê o motivo. Uma execução por projeto, com progresso e **Cancelar** (encerra a IA e não marca nada).
- **Descubra nas regras** (na barra do tópico de regras e da ideia, com Claude ou Codex instalado): você pode dar um
  **contexto inicial** (opcional) sobre o que quer fazer; ele entra em todos os prompts, além do título e da
  descrição. A IA, só com leitura, propõe **globs**; depois faz uma **entrevista** (até 4 perguntas por rodada, 3
  rodadas, com "Gerar com o que já tenho") e sugere regras `must`/`should`. Globs catch-all (`**`, `*`, `**/*`) ou
  que não casam nenhum arquivo são descartados, regras que duplicam ou conflitam com as existentes vêm sinalizadas
  e desmarcadas, e nada é removido. Na ideia as regras entram como rascunho e os globs ficam em `paths`. Por fim a
  IA reescreve a **descrição** (na ideia: Problema, Proposta, Escopo e Critérios de aceite; no tópico: quando ele
  se aplica), mostrada antes/depois para aceitar ou manter a atual, e sugere **tags** (as novas começam
  desmarcadas). Cada aceite é um único ⌘Z; editar o tópico/ideia durante a chamada descarta a resposta.
- **Markdown de documentos e ideias**: Editar formata o próprio campo de texto, mantendo o markdown original.
  A sintaxe fica esmaecida fora da linha/bloco do cursor, e imagens anexadas aparecem no editor. Dividir e Ler
  continuam disponíveis, com fundo herdado da janela; ⌘E alterna edição/leitura e ⌘Z/⇧⌘Z desfaz/refaz.
- **Ideias**: brainstorm com status, tags, globs (`paths`), texto markdown e regras rascunho. "Promover" cria um tópico
  de regras real com essas regras e globs (se o tópico já existe, os globs são somados; globs que não casam mais
  nenhum arquivo são avisados antes). Apagar esse tópico (no app, no Finder ou com `vibedeck ideas unpromote`)
  despromove a ideia: o vínculo some, "Aprovada" volta para "Explorando" e as regras rascunho ficam.
- **Implementar ideia**: o botão "Verificar" pede à IA (sem reescrever nada) o veredito se a ideia é **viável** (dá para implementar sem
  decisões em aberto) ou o que falta; o veredito fica em `readiness`. O botão "Implementar" só habilita com regras e
  veredito viável e atual: qualquer mudança em título, texto, globs ou regras o invalida, e "Verificar" refaz só essa
  avaliação. No app, ideias `approved` com avaliação viável atual oferecem **Workflow**, **Execução padrão** e **Cancelar** antes de promover regras ou iniciar a implementação. Sem workflows, só aparecem Execução padrão e Cancelar, sem catálogo. O seletor permite escolher um workflow existente ou adicionar itens do catálogo por seleção explícita. No chat, o modo explícito é respeitado; pedidos sem modo aguardam a escolha. Execução padrão usa `IdeaImplementation.prompt`. Workflows recebem o UUID recuperável da ideia; mudanças de título ou descrição não mudam o vínculo. Havendo execução anterior, **Retomar** preserva o estado e **Reiniciar** começa na primeira etapa. A confirmação relê a avaliação atual no disco. Cancelar não inicia nem promove. CLI e MCP continuam sem a pergunta de modo. Após confirmar, as regras são promovidas/sincronizadas e a implementação segue as regras e o check.
  Ao clicar em "Salvar avaliação", um veredito viável em ideia com regras marca o status como `approved`, junto com o `readiness` em um único passo de desfazer. Isso não é promoção: `promotedTopic` continua vazio, nenhum tópico é criado e as regras continuam rascunho. Ideias fechadas ou já promovidas mantêm o status; vereditos não viáveis não alteram o status. Rodar Descubra/Verificar sem salvar não aprova a ideia.
- **Dependências entre ideias**: no detalhe da ideia, **Dependências** escolhe várias ideias do projeto (inclusive
  as Implementadas, que somem da sidebar) e remove cada vínculo pelo ✕, com desfazer; **Dependentes** mostra quem
  depende diretamente dela, derivado das outras ideias (sem lista inversa no JSON). Só uma dependência `done`
  libera a implementação; qualquer outro status, ou uma ideia apagada, bloqueia o botão Implementar, os pedidos no
  chat e o início/retomada/reinício por workflow, com os motivos em pt-BR, antes de promover regras, criar run ou
  chamar o provedor. A aprovação continua possível, e concluir a última dependência não inicia nada sozinho.
  O Core recusa autorreferência, ideia inexistente e ciclos sem gravar nada.
  "Copiar prompt" leva esse pedido para a área de transferência, usando o tópico promovido ou as regras
  rascunho, sem promover a ideia. Está disponível mesmo sem provedor de IA e confirma com "Copiado".
- **Agentes**: nome, modelo e prompt (markdown) de agentes do VibeDeck. Os **próximos passos** apontam para
  outros agentes, comandos ou skills do VibeDeck e formam um fluxo; `vibedeck agents flow <agente>`
  (ou o botão "Copiar fluxo") gera o JSON que orquestra a IA. "Importar do Claude Code" traz os `.md` de
  `.claude/agents` (projeto e usuário); "Importar de Codex" traz `.codex/agents/*.toml`.
- **Criar e editar com IA**: com Claude Code ou Codex instalado, as listas de Agentes, Comandos, Skills e Workflows
  têm **Criar com IA** e o detalhe de cada item tem **Editar com IA**. Você descreve o que quer, a IA (somente leitura:
  Read/Glob/Grep no Claude, `workspaceWrites=false` no Codex) devolve a proposta completa em JSON validado e você refina com
  novos pedidos quantas vezes quiser. Nada é gravado antes do aceite, que é um único passo de undo (⌘Z). Há botão de
  cancelar, timeout de 240 s e uma operação por projeto por vez; editar descarta a resposta se o item mudou durante a
  chamada. Criar nunca sobrescreve (slug único) e grava com `author: ai`. No CLI/MCP, a IA que chama usa
  `vibedeck ai item-prompt <tipo> --request "…" [--item <ref>]` (MCP `item_ai_prompt`) para obter prompt e schema e
  `vibedeck ai item-apply <tipo> --file proposta.json [--item <ref>]` (MCP `item_ai_apply`) para validar e gravar.
- **Kits pré-definidos**: o botão nas listas e páginas de Agentes, Comandos, Skills e Workflows abre os kits
  **Manutenção de sistema** e **Desenvolvimento de novas ferramentas**. Confira os conteúdos, selecione itens
  ou um kit inteiro e confirme em **Adicionar selecionados**. Workflows exigem selecionar também seus agentes,
  comandos e skills; as dependências faltantes aparecem antes de confirmar. Nada é criado só por abrir o catálogo.
  Cada adição cria cópias comuns em `.vibedeck/`, editáveis manualmente ou por IA, sem sobrescrever itens existentes.
  Repetir a adição gera slugs distintos e remapeia as referências para as novas cópias. O conjunto aparece ao vivo
  e pode ser desfeito/refeito em um único passo (⌘Z / ⇧⌘Z), preservando os itens que já existiam.
  CLI: `vibedeck kits list --json`, `vibedeck kits add manutencao --ai --json` ou
  `vibedeck kits add manutencao:agent manutencao:command`. MCP: `ai_catalog(kind: "kits")` e
  `add_kit(items: ["manutencao"])` (author=ai). Os ids de kits completos selecionam explicitamente todos seus itens.
- **Comandos**: o mesmo fluxo dos agentes, no formato dos slash commands — prompt (markdown, com `$ARGUMENTS`),
  descrição, argumentos, modelo e próximos passos. Um agente pode ter um comando como próximo passo e vice-versa;
  `vibedeck commands flow <comando>` gera o JSON do fluxo. "Importar do Claude Code" traz os `.md` de
  `.claude/commands` (subpastas viram namespace: `git/commit.md` → `git:commit`). O Codex também importa
  prompts legados de `.codex/prompts`; comandos do VibeDeck são expandidos pelo painel.
- **Skills**: o mesmo fluxo dos agentes e comandos, no formato do `SKILL.md` — instruções (markdown), descrição
  (quando usar a skill; é o que a dispara), modelo e próximos passos. Agentes, comandos e skills podem ser próximos
  passos uns dos outros; `vibedeck skills flow <skill>` gera o JSON do fluxo. "Importar do Claude Code" traz o
  `SKILL.md` de cada pasta em `.claude/skills` (projeto e usuário). O Codex usa a descoberta nativa de skills,
  incluindo `.agents/skills` e plugins. Os caminhos dos arquivos de apoio são preservados.
- **Workflows**: orquestram um fluxo inteiro, com nome, para usar sempre que quiser. Cada **etapa** roda um agente,
  comando ou skill do VibeDeck (o mesmo pode repetir); a primeira é o início. Cada etapa tem **transições**
  avaliadas sobre o resultado: primeiro as de **veredito** ("= APROVADO", a última linha do resultado), depois as
  de **condição** ("se ‹condição›", em linguagem natural), por fim um "senão" opcional — podem voltar a etapas
  anteriores (laços). Quando nenhuma transição vale, o workflow termina; `maxSteps` (padrão 25) e o máximo de vezes
  por etapa (`maxVisits`) evitam laço infinito. Na página do workflow, **Etapas** edita e **Fluxo** mostra o
  diagrama: cada transição é uma seta com o veredito ou a condição, laços (voltas) em laranja à esquerda, saltos à
  direita e "Fim" tracejado onde nenhuma transição vale; passar o mouse numa etapa destaca para onde ela pode ir, e
  o duplo clique abre o agente/comando/skill.
- **Execuções**: "Executar" pede a entrada e cria a execução em `.vibedeck/runs/<workflow>/<entrada>/`.
  No app, Claude e Codex usam o motor do VibeDeck para controlar a execução;
  cada etapa abre uma sessão com contexto limpo. Ambos usam o mesmo motor de vereditos, condições,
  perguntas e limites de visitas. O provedor fica gravado na execução; continuar mantém esse provedor.
  As perguntas das etapas aparecem no painel e suas respostas são registradas antes da retomada.
  Iniciar ou retomar abre, ao lado do chat, o **visualizador da execução**: o diagrama do workflow com a etapa
  atual e as transições percorridas, o estado da execução e os agentes e subagentes informados pelo provedor
  (eventos `task_*` do Claude Code, `collabAgentToolCall` do Codex). Arraste a divisão para ajustar a largura,
  expanda ou oculte o painel sem interromper a execução. A conversa guarda a referência à execução
  (`workflowRun`); ao reabri-la, agentes salvos como em andamento aparecem sem confirmação de atividade.
  `vibedeck workflows flow <workflow>` continua gerando o JSON do workflow sem estado.
- **Conduzir** (só neste repositório): o fluxo do claude-kit portado para o VibeDeck, com issues do GitHub
  (e o Status do GitHub Projects) no lugar do Plane. Comandos `registrar-task-do-github → viabilizar → planejar →
  criticar → implementar → avaliar → abrir-pull-request` (e `buscar-review` para PR já publicado), agentes
  `viabilizador`, `explorador`, `planejador`, `critico`, `implementador`, `verificador` e `revisor-pr`, e a skill
  `status-no-github-project`. Requer `gh auth refresh -s project`.
- **Gerar documentos**: No app, a lista de **Docs** oferece **Gerar documentos** quando há Claude Code ou Codex instalado. A geração usa o provedor ativo somente para leitura, com cancelamento e timeout de 180 segundos por chamada. A proposta permite editar título e conteúdo, pré-visualizar Markdown, descartar documentos e aceitar todos ou apenas os selecionados. Nada em `.vibedeck/docs` é gravado antes do aceite. São propostos até 8 documentos; campos vazios e conteúdos acima de 40.000 caracteres são descartados. O prompt exige referências aos arquivos de origem. O aceite cria Markdown com `author: ai` no frontmatter e slugs únicos, atualiza a lista e é um único passo de undo. Os documentos podem ser lidos por `vibedeck docs cat` e MCP `read_doc`; criação com autoria também está disponível em `vibedeck docs new "Título" --body "Conteúdo" --ai` e MCP `write_doc` (`title`, `content`, `generated: true`).
- **Docs vinculados**: todo `.md` da raiz do repositório (como `README.md`) aparece em **Docs** como um symlink
  relativo em `.vibedeck/docs/`; editar o doc edita o arquivo de origem. Um vínculo quebrado vira aviso e, se o
  slug colidir com outro doc, o vinculado ganha o sufixo `-raiz`. `vibedeck docs unlink <slug>` remove só o vínculo
  (a origem nunca é tocada) e `vibedeck docs link <arquivo>` vincula de novo.
- **Início guiado**: ao abrir uma pasta sem `vibedeck.json` (ou ao criar um projeto novo), o app oferece a stack, os
  padrões e os agentes, comandos e skills já existentes em `.claude/` e `.codex/`. Nada é cadastrado sem sua
  escolha, e **Pular** é retomável. CLI: `vibedeck onboarding` (estado), `onboarding skip`, `onboarding complete`
  e `onboarding import <tipo>:<nome>` (`agent`, `command` ou `skill`).
- **Tags**: docs (frontmatter `tags: [a, b]`), revisões, regras, ideias, agentes, comandos, skills e workflows. Cada seção da sidebar abre
  uma lista filtrável por texto e por `#tag`.
  A sidebar também tem um campo de busca por texto e `#tag` para os filhos de todas as seções;
  múltiplas tags e o texto são combinados. Ela omite revisões sem itens abertos e ideias implementadas,
  que continuam acessíveis nas listas centrais e nas abas já abertas.

- **Grafo**: a visualização usa recursos locais e começa por comunidades, com até 180 nós e 300 relações
  por vista. Oferece busca, zoom, centralização, inspeção por teclado e origem no Finder quando válida.
  **Gerar** e **Atualizar** executam estrutura de código e análise semântica com o provedor selecionado;
  não iniciam ao abrir a aba. Uma execução por projeto, com progresso e cancelamento. A publicação do
  JSON e HTML ocorre após validação, preservando o resultado anterior em falhas. A data mostrada é a
  última geração registrada, não a data do arquivo. Para exportar a visualização offline pelo terminal:
  `vibedeck graph export` ou MCP `export_graph` (não consomem IA). Validação do renderer: `node scripts/test-graph-renderer.cjs`.
- **IA no app**: o painel **IA** na sidebar (⇧⌘C) oferece Claude e Codex em uma interface compartilhada.
  Claude usa `claude -p` em stream-json; Codex usa `codex app-server --stdio`. Ambos oferecem streaming,
  histórico persistente, perguntas, aprovações, interrupção, anexos e referências a outras conversas.
  Cada conversa mantém seu provedor e sua sessão. Trocar de provedor cria uma nova conversa, com a opção
  de levar a anterior como referência. Históricos antigos continuam sendo Claude.
  O Codex consulta seu catálogo de modelos e esforços e respeita suas políticas de aprovação e sandbox.
  O toggle **Auto** ativa a revisão automática de permissões do Codex, mantendo o sandbox. A escolha
  fica salva no app para conversas novas, retomadas e workflows; pode ser alterada entre respostas.
  Desligado, os pedidos de aprovação voltam ao usuário. Requer um Codex CLI com suporte a Auto-review.
  Agentes, comandos e skills têm configurações opcionais de modelo/esforço por provedor; os registros
  e workflows ficam compartilhados em `.vibedeck`, mesmo sem nenhum provedor instalado.
  `/` lista comandos e skills; no Codex inclui os registros do VibeDeck e `/agent:<slug>`, além de
  `/clear`, `/compact` e `/context`. `@` lista arquivos e conversas; `!` roda um comando de terminal e
  inclui sua saída na próxima mensagem. ↑/↓ navegam, Tab ou ↩ aceitam, Esc fecha.
  **Terminal** (⌃`) abre um terminal interativo de verdade (SwiftTerm), com o seu shell de login na pasta
  do projeto, sempre numa aba nova — cada aba é uma sessão própria ("Terminal", "Terminal 2"…). O shell
  continua rodando ao trocar de aba; fechar a aba encerra o shell, e `exit` no shell fecha a aba. Escolher
  outro item na sidebar com um terminal ativo abre o item ao lado, sem derrubar o terminal. Programas
  interativos chamados com `!` (`vim`, `less`, `top`, `ssh`, REPLs sem script, `git commit` sem `-m`…)
  abrem num terminal novo.
  As ações de IA funcionam com apenas um dos provedores instalado. Os registros permanecem acessíveis sem IA.

Schemas: `schema/v1/` (servidos pelo Worker em `worker/`).

## Build

CLI e MCP (Linux ou macOS) só precisam do Rust:

```sh
cargo build --release -p vibedeck    # target/release/vibedeck
scripts/test.sh --rust               # cargo test --workspace
```

O app requer macOS 26+ e Xcode 27 (SDK do macOS 27):

```sh
scripts/build-app.sh --install-cli   # build/VibeDeck.app + build/VibeDeck-<versão>.dmg + ~/.local/bin/vibedeck
CONFIG=debug scripts/build-app.sh --no-dmg # desenvolvimento local: app e CLI, sem gerar instalador
VIBEDECK_BIN=/caminho/vibedeck scripts/build-app.sh   # usa um binário Rust já compilado (ex.: universal, de CI)
open build/VibeDeck.app              # ou: open -a build/VibeDeck.app <pasta-do-projeto>
scripts/test.sh                      # Rust + testes do app (o app só no macOS)
scripts/test.sh --app                # só os testes do app
```

O script compila o Core Rust (`cargo build`) e o app (SwiftPM), reutilizando os caches. O modo padrão
continua sendo release com DMG; `--no-dmg` pula apenas a geração do instalador e pode ser combinado com
`--install-cli` em qualquer ordem. `CONFIG=debug|release` escolhe o perfil.

> Sem o Xcode (só Command Line Tools), o SDK 27 não compila SwiftUI: `@State` virou macro e o
> plugin `SwiftUIMacros` só vem no Xcode. Nesse caso `scripts/env.sh` cai para o SDK 26.x e os
> testes rodam com `scripts/test.sh`.

O terminal usa a JetBrains Mono Nerd Font Mono (SIL OFL 1.1, `assets/fonts/`), que o
`build-app.sh` copia para `Contents/Resources/Fonts`. Rodando com `swift run`, ele cai para a
fonte monoespaçada do sistema.

## Atalhos

| | |
|---|---|
| ⌘O | Abrir projeto |
| ⌘W / ⇧⌘W | Fechar a aba ativa (com uma só aba, fecha a janela) / fechar a janela |
| ⌘Z / ⇧⌘Z | Desfazer / refazer (docs têm histórico próprio, sobrevive ao autosave) |
| ⌘E | Alternar editar/ler no doc |
| ⇧⌘N | Focar campo de novo item de revisão |
| ⌥⌘I | Mostrar/ocultar painel do item |
| ⇧⌘C | Abrir o painel IA |
| ⌃` | Abrir um terminal novo (em aba nova) |

## IA

```sh
vibedeck status
vibedeck review list --status open --json
vibedeck review add "Tela de login" "Esconder link de cadastro" --kind hide --file src/Login.tsx --ai
vibedeck review set <id-ou-prefixo> --status done
vibedeck rules new "Interface" --path "Sources/VibeDeckApp/**"
vibedeck rules add interface "Nunca usar minWidth no root da janela"
vibedeck rules for crates/vibedeck/src/main.rs --json
echo '[{"ruleId":"<prefixo>","verdict":"pass","note":"..."}]' | vibedeck rules check --task "..." --item <id>
vibedeck rules test crates/vibedeck/src/main.rs   # roda os scripts das regras aplicáveis
vibedeck rules set-test <regra> --command .vibedeck/tests/geral/ab12cd34.sh   # ou --manual --reason "..." / --clear
vibedeck hook install                        # liga o hook Stop (portão de regras) neste projeto
vibedeck hook install --agent codex          # o mesmo no Codex (.codex/hooks.json)
vibedeck ideas new "Modo offline" --tags futuro && vibedeck ideas promote modo-offline
vibedeck ideas unpromote modo-offline        # apaga o tópico e despromove a ideia
vibedeck ideas depend app-mobile modo-offline   # app-mobile só implementa depois de modo-offline done
vibedeck ideas undepend app-mobile modo-offline # MCP: update_idea com dependencies (lista completa)
vibedeck agents import                       # traz os agentes do Claude Code
vibedeck agents next revisor testador        # testador atua depois do revisor
vibedeck agents flow revisor                 # JSON do fluxo para o prompt
vibedeck commands import                     # traz os comandos do Claude Code
vibedeck commands new commit --argument-hint "<mensagem>" --prompt "Commite: \$ARGUMENTS"
vibedeck agents next revisor commit --kind command   # o comando roda depois do revisor
vibedeck commands flow commit                # JSON do fluxo a partir do comando
vibedeck skills import                       # traz as skills do Claude Code (.claude/skills/<nome>/SKILL.md)
vibedeck agents next revisor graphify --kind skill  # a skill roda depois do revisor
vibedeck skills flow graphify                # JSON do fluxo a partir da skill
vibedeck workflows new "Revisão" --input "<tarefa>"   # workflow nomeado
vibedeck workflows step revisao autor && vibedeck workflows step revisao revisor   # etapas (a 1ª é o início)
vibedeck workflows route revisao autor revisor               # senão → revisor
vibedeck workflows route revisao revisor autor --when "encontrou problemas"   # volta (laço)
vibedeck workflows route revisao revisor autor --verdict REPROVADO   # pelo veredito (última linha do resultado)
vibedeck workflows visits revisao revisor 3  # no máximo 3 vezes por ciclo
vibedeck workflows show revisao              # etapas e transições
vibedeck workflows flow revisao --input "PR 12" [--prompt]   # JSON (ou prompt) que orquestra a IA
vibedeck runs start conduzir --input "#12" [--prompt]   # cria/retoma a execução (prompt do orquestrador)
vibedeck runs next conduzir/12 | vibedeck runs step conduzir/12   # próxima ação | prompt da etapa (subagente)
vibedeck runs record conduzir/12 --verdict APROVADO --summary "..."   # registra o veredito e anda
vibedeck runs questions conduzir/12 --open && vibedeck runs answer conduzir/12 1 "main"
vibedeck runs show conduzir/12 | vibedeck runs list --status waiting
vibedeck tag review tela-de-login ui mvp     # substitui as tags (doc | review | rules | idea | agent | command | skill | workflow | stack | pattern)
vibedeck mcp install                         # registra o servidor MCP no Claude Code (--scope local/project/user)
vibedeck usage install                       # liga a statusline do Claude Code ao VibeDeck (mantém a atual encadeada)
vibedeck usage [--json]                      # limite da sessão (5h) e da semana, com horário de reset
vibedeck onboarding                          # início guiado: mostra o estado e os recursos detectados (--json)
vibedeck docs unlink readme                  # desfaz o vínculo de um doc com um .md da raiz (a origem não é tocada)
vibedeck docs link README.md                 # vincula de novo
```

### Codex: configuração e registros

Requer Codex CLI com App Server e autenticação local (`codex login`). O painel conecta o MCP do projeto
por configuração da própria sessão, sem alterar seu arquivo de configuração. Para clientes externos:

```sh
vibedeck mcp install --provider codex                 # .codex/config.toml do projeto
vibedeck mcp install --provider codex --scope user    # ~/.codex/config.toml
vibedeck mcp uninstall --provider codex
vibedeck agents import --provider codex
vibedeck commands import --provider codex
vibedeck skills import --provider codex
vibedeck agents set revisor --provider codex --model <modelo> --effort high
vibedeck runs start revisar --provider codex --input "feature" --prompt
vibedeck usage --provider codex --json
```

O instalador preserva as demais configurações. `--force` substitui apenas um registro gerenciado pelo VibeDeck.
Os agentes nativos importam `name`, `description`, `model`, `model_reasoning_effort` e
`developer_instructions` de TOML. Outras configurações nativas continuam no arquivo original.
Arquivos inválidos são reportados; registros existentes são preservados salvo `--overwrite`.
As tools MCP de importação e `workflow_run_start` também aceitam `provider: "codex"`.

### Servidor MCP

`vibedeck mcp` inicia o servidor MCP por stdio (`vibedeck mcp serve` é equivalente; `-C <dir>` escolhe o projeto).
O projeto traz um `.mcp.json` com esse servidor; para registrá-lo em outros clientes:

```sh
vibedeck mcp install                              # Claude Code, escopo local
vibedeck mcp install -s project                   # grava .mcp.json do projeto (versionável)
vibedeck mcp install -s user --provider claude    # todos os projetos do usuário
vibedeck mcp install --provider codex             # Codex (veja a seção abaixo)
vibedeck mcp uninstall
ssh servidor vibedeck mcp -C /caminho/do/projeto  # o mesmo servidor, remoto, por SSH
vibedeck hook install                             # hook Stop (portão de regras)
```

O modo `--app` (`vibedeck mcp --app`) é o usado pelo app macOS: acrescenta tools extras e avisos de mudança
em `.vibedeck/`. O CLI e o MCP funcionam em Linux e macOS; o binário precisa estar no `PATH`.

### Limites de uso

O rodapé da sidebar mostra quanto da **sessão (5h)** e da **semana** do plano do Claude Code já foi usado e
quando cada uma reinicia. Os números vêm da statusline do Claude Code: `vibedeck usage install` (ou o botão
"Mostrar limites do Claude Code" no app) faz ela rodar `vibedeck usage record`, que grava o uso em
`~/Library/Application Support/VibeDeck/claude-usage.json`. Uma statusline que já existia continua aparecendo
(`--then`), e `vibedeck usage uninstall` a devolve. Só funciona com login de assinatura (Pro/Max); com chave de
API o Claude Code não informa limites. Agentes leem o mesmo dado pela tool MCP `claude_usage`.

Com Codex selecionado, o rodapé consulta os limites diretamente no App Server, com as janelas e
resets informados pela conta. `codex_usage` oferece os mesmos dados pelo MCP; contas que não
fornecem limites mostram essa indisponibilidade. O menu de integrações instala MCP e hooks;
hooks novos do Codex precisam ser aprovados com `/hooks` no terminal do Codex.

## Logs e diagnóstico

O app, o CLI e o MCP registram erros, falhas e crashes em `~/Library/Application Support/VibeDeck/logs/` (no Linux, `$XDG_DATA_HOME/VibeDeck/logs`), um
arquivo JSON Lines por dia (fora do projeto e do git, mantido por 14 dias). Só entram nomes, ids, códigos e
tamanhos, nunca o conteúdo de prompts, docs ou ideias. Se o app fechar de forma inesperada, ele avisa na próxima
abertura e associa o relatório de crash do macOS. Para ver os logs no app, use **Ajuda › Diagnóstico…**, que tem
filtros e o botão "Copiar Relatório".

```sh
vibedeck logs [--since 24h] [--level warning] [--component mcp] [--all-projects] [--json]
vibedeck logs report                         # texto para colar numa issue
vibedeck logs crashes                        # crashes do app
vibedeck logs path                           # pasta dos logs
```

Agentes leem os mesmos dados pelos resources MCP `vibedeck://logs` e `vibedeck://logs/crashes`.


As interações do app são ações `ui.*` de nível Info: botões, menus, atalhos, seleções e confirmação de
campos (Return ou perda de foco, sem uma entrada por tecla). Cada ação tem um id em `context.action`,
um controle estável em `context.control` e seu rótulo em `context.label`. Gravações `store.*`, chamadas
`ai.*` e checks `rules.*` carregam a mesma correlação. As gravações incluem arquivo relativo e nome do undo;
mudanças externas têm `origin=external`. CLI e MCP registram nome da operação e duração em ms.

Em **Ajuda › Diagnóstico…**, escolha **Info** e use **Id da ação** ou **Filtrar esta ação** no detalhe
para ver a ação e suas reações. A busca também procura no contexto.

```sh
vibedeck logs --level info --since 5m --component app --json
vibedeck logs --level info --action ID --json
vibedeck logs --level info --component cli mcp --since 24h --json
```

No MCP, `read_logs` aceita `level` (padrão `info`), `since`, `components`, `action` e `limit`.
Exemplo: `{"level":"info","since":"5m","components":["app"],"action":"ID"}`.
Os resources `vibedeck://logs` e `vibedeck://logs/crashes` mantêm os filtros de aviso/crash.
Os logs seguem fora do projeto, em Application Support, como JSON Lines por dia com `O_APPEND`;
nunca incluem conteúdo de campos, prompts, documentos ou argumentos de ferramentas.

## Worker (schemas)

```sh
cd worker && npm install
npm run dev        # http://localhost:8787/v1/project.schema.json
npm run deploy     # depois: scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev
```


## Eficiência e consumo de IA

A política de eficiência é distribuída com o app, CLI e MCP para todos os projetos. O guia inicial gerado
em `.vibedeck/AGENTS.md` contém as obrigações; `.vibedeck/guide.md` guarda a referência completa.
Abrir o projeto no app ou usar o CLI/MCP atualiza esses arquivos gerados. Prompts de agentes, comandos,
skills e workflows personalizados não são reescritos.

- **Contexto sob demanda:** consulte `vibedeck ai guide` e depois `--section <n>`. Use
  `vibedeck ai catalog agents|commands|skills|workflows|rules` (`--offset`, `--limit`) para descobrir registros
  sem carregar seus prompts. As listagens anteriores mantêm seu formato.
- **Conversas mencionadas:** referências grandes viram snapshots locais imutáveis, com leitura por trechos.
  O botão “Incluir conversas completas” no chat permite enviar tudo explicitamente. Se o snapshot falhar,
  o conteúdo integral é enviado. Snapshots são dados de referência, não instruções, e ficam disponíveis
  mesmo quando a conversa original muda. `vibedeck ai context <id> --offset 0 --limit 4000` lê uma página.
- **Workflows:** etapas e limites continuam obrigatórios; todas as decisões respondidas são preservadas.
  O histórico recente traz referências; saídas completas do painel Codex ficam em `outputs/` dentro da execução.
  Histórico anterior e evidências podem ser recuperados em `run.json`, sem corte de caracteres nas novas saídas.
- **Modelos simples:** exploração e delegação podem ser proporcionais à tarefa, mas critérios de conclusão
  e validações não são dispensados. “Descubra” e verificação manual de regras permitem uma recuperação
  de resposta inválida no mesmo modelo. Persistindo a falha, informam a limitação; não trocam modelo/provedor.
  Cancelamentos, erros de transporte e tarefas com escrita não são repetidos automaticamente.
- **Geração em lote:** o menu “Gerar verificações” permite escolher Claude ou Codex, usa as configurações
  de modelo/esforço do painel e valida os registros das regras selecionadas ao terminar.
- **Métricas:** “Consumo por tarefa”, na área do provedor, e “Consumo de IA”, no chat, mostram tentativas,
  duração, modelo, caracteres na entrada da tarefa (sem instruções de sistema e leituras posteriores) e tokens/custos informados. `vibedeck ai usage --json` consulta os mesmos
  dados; `--clear` limpa só as métricas. Caracteres não são tokens; ausência de contagem não é zero.
  Chamadas externas e retomadas sem contador inicial podem ter cobertura parcial. Não há estimativa de preço.

Equivalentes MCP: `ai_guide`, `ai_catalog`, `ai_context` e `ai_usage` (`clear: true` somente quando solicitado).
O app também permite consultar o guia por assunto. Métricas e snapshots ficam localmente em
Application Support/VibeDeck/ai, separados por diretório de projeto, sem envio de telemetria. Os registros de
consumo não guardam texto de prompts; snapshots guardam apenas o contexto explicitamente referenciado.

Validação: `scripts/test-ai-efficiency.sh` testa economia do contexto inicial (meta de pelo menos 30% em
cenários redundantes), integridade das referências, contratos, recuperação e contagem. Isso mede o que
VibeDeck controla; redução real de tokens e qualidade de cada modelo exigem comparação de tarefas reais
com o mesmo modelo e estado inicial, incluindo recuperações. Não há promessa de economia fixa por tarefa.

### Paridade entre Claude e Codex

Os dois provedores compartilham o contrato de sessões, eventos e workflows. Cada etapa usa uma sessão limpa. O motor do VibeDeck controla transições, perguntas e limites; uma saída concluída é salva em `checkpoint` antes de avaliar condições. Retomar uma execução interrompida preserva a etapa atual, histórico e respostas. Saídas parciais são referências para conferir o estado antes de continuar.

No Codex, **Planejar** usa somente leitura e apresenta planos completos (`<proposed_plan>`) com ações de aprovar, pedir mudanças e rejeitar. O plano pendente sobrevive ao fechamento da conversa. **Editar projeto** permite escrita no workspace; comandos e acessos adicionais seguem as aprovações do Codex. O controle de aprovação automática é próprio do Codex. Opções sem equivalência, como dois modos com a mesma política, não aparecem duplicadas.

Modelos e esforços explícitos indisponíveis interrompem a operação. A precedência é configuração do recurso, escolha da sessão e padrão do provedor; não há substituição automática. Comandos, agentes e skills registrados no VibeDeck são expandidos e sugeridos nos dois provedores.

| Recursos | Claude | Codex | Evidência automatizada |
| --- | --- | --- | --- |
| Chat, eventos e interrupção | Transporte Claude | Transporte app-server | testes do app (`Tests/VibeDeckAppTests`) |
| Planejamento | Aprovação nativa | Aprovação pelo VibeDeck | testes do app |
| Workflows e perguntas | Motor VibeDeck | Motor VibeDeck | `workflows_core`, `workflows_cli` (Rust) |
| Descubra, documentos, grafo e verificação | Leitura restrita | Leitura restrita | `AIRecoveryTests`, `GraphRunnerTests`, `RuleDiscoverVerdictTests` (app) |
| Geração de testes | Escrita autorizada | Escrita autorizada | `AIRecoveryTests` (app), `rules_cli` (Rust) |
| Importação, CLI/MCP e hooks | Formatos nativos | Formatos nativos | `ai_mcp_install`, `workflows_cli`, `rules_cli`, `mcp_stdio` (Rust), contrato MCP |
| Consumo | Tokens/custo informados | Tokens/limites informados | `ai_cli` (Rust), `scripts/test-ai-efficiency.sh` |
| Coleção de artefatos do Claude | Links do Claude | Recurso exclusivo do Claude | `project_cli`, `project_mcp` (Rust) |

O catálogo de capacidades descreve a integração; erros de versão, autenticação ou conta são apresentados pelo adaptador, sem mudar de provedor. Não há smoke tests automatizados contra os provedores reais: as verificações automatizadas não consomem IA.

### Grupos de itens

Ideias, documentos, temas de revisão e skills podem ser organizados em diretórios aninhados, sem migração dos projetos planos. Use o caminho completo `a/b/slug` como referência; slugs repetidos em grupos diferentes coexistem, e referências simples ambíguas são recusadas. As skills organizam apenas os JSON do VibeDeck, preservando os arquivos importados dos provedores. Regras usam um campo opcional `group` dentro de seu tópico, com IDs e checks preservados.

No app, a sidebar e as listas mostram a árvore, incluindo grupos vazios. O menu permite criar itens/subgrupos, renomear, mover e apagar; arrastar também move. Mover é um único passo de desfazer, atualiza referências e acompanha a seleção pelo ID. Apagar grupos com itens exige confirmação explícita, inclusive para autoria humana.

```sh
vibedeck ideas new "Plano" --reference produto/mobile/plano
vibedeck docs new "Guia" --reference produto/mobile/guia
vibedeck groups create ideas produto/web
vibedeck groups move-item ideas produto/mobile/plano produto/web
vibedeck groups rename ideas produto/web desktop
vibedeck groups list ideas --json
vibedeck groups remove ideas produto/desktop --confirmed
vibedeck groups move-rule <id> interface/layout
```

As listagens JSON incluem `slug` e `group`. No MCP, use `item_groups` (ações `list`, `create`, `move`, `rename`, `move_item`, `delete`) (`confirmed: true` para apagar grupos não vazios). Criações aceitam `reference`; regras usam `move_rule_to_group` e `rename_rule_group`. Caminhos inseguros e destinos existentes são recusados sem sobrescrever arquivos. Anexos continuam resolvendo após movimentos.

O botão **Implementar** reavalia ideias com avaliação ausente ou desatualizada e só inicia a implementação após salvar um resultado positivo para o conteúdo atual.

### Reorganizar o projeto

O botão **Reorganizar** nas listas de Regras, Docs, Ideias e Revisões analisa os quatro conceitos com
Claude Code ou Codex somente leitura. A proposta mostra conflitos, mesclagens, movimentos, criação de
tópicos/subpastas e melhorias de fluxo. Nada muda antes do aceite; o lote aceito tem um único undo/redo.
Conflitos exigem escolher qual manter: os demais são arquivados em `.vibedeck/archive/reorganize/`.
Ideias promovidas, tópicos vinculados e revisões encerradas não podem ser arquivados. Mesclagens
preservam conteúdo, tags, globs e regras; campos incompatíveis bloqueiam o lote. Melhorias criam ideias
com `author=ai`, sem promover regras. Tópicos novos também registram `author` (`human` ou `ai`);
ausência do campo em projetos antigos significa `human`. Tópicos aceitam caminhos aninhados.
Cancelar, timeout de 180 segundos por chamada e mudanças no projeto invalidam a análise. Checks históricos permanecem intactos.
CLI: `vibedeck reorganize prompt`, `analyze --provider claude|codex`, `validate --file resposta.json --fingerprint HASH`
e `apply --file proposta.json --acceptance aceite.json`. O aceite contém `selected` (IDs das ações)
e `conflicts` (ID da ação → chave concept/slug#itemID do item mantido). Sem escolha, conflitos ficam pendentes.
MCP: `reorganize_prompt`, `reorganize_analyze`, `reorganize_validate` e `reorganize_apply`;
proposta e aceite são strings JSON. Analisar e validar nunca aplicam ações automaticamente.

### Projetos remotos via SSH

Na tela inicial, **Conectar via SSH…** permite escolher um alias de `~/.ssh/config` ou informar servidor, porta e usuário. A conexão usa OpenSSH, chaves/agente SSH ou senha; guardar a senha no Chaves do macOS é opcional. Confirme a impressão digital do servidor na primeira conexão. Uma mudança da chave conhecida bloqueia o acesso até verificar a identidade.

O app conversa direto com o servidor: ele executa o `vibedeck mcp` remoto por SSH (o equivalente a `ssh servidor vibedeck mcp -C <pasta>`), então o **binário `vibedeck` precisa estar instalado no servidor**, no `PATH`. Navegue pelas pastas ou digite um caminho; uma pasta sem `vibedeck.json` só é inicializada depois de confirmar **Inicializar projeto**.

Se a conexão cair, o app tenta reconectar sozinho, com intervalos crescentes (1, 2, 4, 8… até 60 segundos); o painel SSH também oferece reconexão manual e entrada de senha. Enquanto estiver offline, o projeto fica em **somente leitura**: o app mostra a última leitura guardada em cache no Mac, sem edição offline e sem conflitos de sincronização. Ao reconectar, os dados são recarregados do servidor.

O terminal abre no servidor e no diretório do projeto. Scripts de regras, chat, Descubra, gerações e workflows também executam remotamente. **Claude Code ou Codex deve estar instalado e autenticado no servidor**; a instalação no Mac não substitui esse requisito. O app não instala nem troca provedores automaticamente. Use **Terminal SSH** para autenticar o provedor.
