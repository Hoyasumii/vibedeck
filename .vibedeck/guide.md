# VibeDeck — guia para agentes de IA

Este diretório é gerenciado pelo app **VibeDeck**: links, documentos, revisões, **regras**, **ideias**, **agentes**,
**comandos**, **skills** e **workflows** do projeto, em arquivos locais que você (agente) pode ler e editar.

## ⚠️ Regras — obrigatório antes de concluir qualquer tarefa

Nenhuma tarefa está concluída sem passar pelas regras do projeto:

1. `rules_for` (MCP) ou `vibedeck rules for <arquivos> --json` com os arquivos alterados (e o item de revisão,
   se houver): lista as regras de script (`check: "script"`) e só conta as manuais (`manualRules`).
2. `submit_rule_check` (ou `vibedeck rules check`) sem `results`: roda os scripts sozinho (veja "Testes de regras").
   As manuais ficam em `pending` e **não** entram nesse fluxo.
3. Se `passed` for `false`, corrija e envie outro check; só diga que terminou quando passar. `should` que falham
   não bloqueiam: avise o usuário e diga quantas manuais ficaram em `pending`.
4. Manuais **só quando o usuário pedir** (ou para fechar item de revisão com manual `must`): `rules_for` com
   `include_manual=true` (CLI: `rules for --manual`), confira o código e envie `submit_rule_check` com
   `verify_manual=true` (CLI: `rules check --manual`), `pass`, `fail` ou `na` e evidência para **cada** manual.

Item de revisão com regras (`rules`, ou `target.file` casando os `paths` de um tópico) só vai para `done` com
check aprovado para ele, incluindo as manuais `must` (passo 4); as manuais `should` não o seguram.

Com o hook `Stop` (`vibedeck hook install`, ou `--agent codex`), o Claude Code ou o Codex não encerra a resposta
enquanto um arquivo alterado na sessão tiver regras sem check aprovado posterior; o bloqueio lista o que falta.

## Stack — consulte antes de implementar

`stack` no `vibedeck.json` lista as tecnologias de destaque do projeto (ids do [Skill Icons](https://skill-icons.alanreisanjo.workers.dev)),
na ordem, com `note` dizendo como o projeto usa cada uma. Antes de implementar algo, leia a stack (`list_stack` /
`vibedeck stack --json`): prefira essas tecnologias e siga as notas. Para mudar: `add_stack` / `vibedeck stack add <ids…> --ai`,
`remove_stack` / `vibedeck stack remove <ids…>`, `update_stack` / `vibedeck stack note <id> "..."`; ache ids com
`search_stack_icons` / `vibedeck stack search <texto>`. O badge da stack no README.md (bloco
`<!-- vibedeck:stack:start -->`) é regravado a cada mudança; não o edite à mão.
Sem MCP, use o CLI; sem ambos, leia `stack` e suas notas diretamente em `vibedeck.json`.
O badge mostra tecnologias, mas não inclui as notas de uso.

## Padrões de projeto — siga ao implementar

`patterns` no `vibedeck.json` lista os padrões de código que o projeto adotou (TDD, arquitetura hexagonal, DDD,
CQRS…), com `note` dizendo como o projeto aplica cada um. Antes de implementar, leia os padrões (`list_patterns` /
`vibedeck patterns --json`) e escreva o código seguindo-os, para manter o projeto consistente.
Cada padrão aponta por `topic` para um tópico em `.vibedeck/rules/` (`paths` dá o escopo),
então as regras dele chegam pelo `rules_for` e são cobradas no check como qualquer outra.
Para mudar: `pattern_catalog` / `vibedeck patterns catalog` mostra o catálogo; `add_pattern` / `vibedeck patterns add <ids…> --ai`
(ou `--custom "<nome>" --rule "..."`), `remove_pattern` / `vibedeck patterns remove <id>` (apaga o tópico),
`update_pattern` / `vibedeck patterns note|paths <id> ...`. Apagar o tópico de um padrão retira o padrão.
`list_patterns` e `vibedeck://patterns` incluem notas, regras e escopos. Já `vibedeck patterns --json`
retorna os registros do manifesto: consulte também `rules_for` / `vibedeck rules for <arquivos> --json`
antes de implementar. Sem MCP/CLI, leia `patterns` em `vibedeck.json`, abra os tópicos referidos por
`topic` em `.vibedeck/rules/` e os demais tópicos aplicáveis: `paths` vazio é global; com globs,
só vale quando algum arquivo da tarefa casa. `sourcePattern` no tópico identifica o padrão.
Releia notas, regras e escopos após mudanças; o contexto não é uma cópia fixa no prompt.
Ausência de `patterns` (ou lista vazia) significa nenhum padrão cadastrado, sem dispensar as outras regras.

## Estrutura

```
vibedeck.json                 # declara o projeto: nome, links, coleção Claude (claude), stack, padrões (patterns), tipos de revisão (reviewKinds)
.vibedeck/
  AGENTS.md                   # este arquivo (regenerado pelo app; não edite)
  docs/<slug>.md              # documentos markdown (título = frontmatter `title:` ou primeiro `# `)
  reviews/<slug>.json         # um grupo (tema) de itens de revisão por arquivo
  rules/<slug>.json           # um tópico de regras por arquivo (paths = globs de escopo)
  ideas/<slug>.json           # uma ideia por arquivo (brainstorm, com regras rascunho)
  agents/<slug>.json          # um agente do VibeDeck por arquivo (nome, modelo, prompt, próximos passos)
  commands/<slug>.json        # um comando do VibeDeck por arquivo (prompt com $ARGUMENTS, próximos passos)
  skills/<slug>.json          # uma skill do VibeDeck por arquivo (descrição de quando usar, instruções, próximos passos)
  workflows/<slug>.json       # um workflow do VibeDeck por arquivo (etapas e transições condicionais)
  runs/<workflow>/<execução>/ # execuções de workflows: run.json (estado; não edite) + o que as etapas gravam
  tests/<tópico>/<regra>.sh   # scripts gerados a partir das regras (ver "Testes de regras")
  checks/*.json               # verificações de regras registradas (histórico; não edite)
  attachments/<dono>-<nome>   # arquivos anexados a docs/ideias; no markdown: `![](../attachments/x.png)`
```

No painel **Links**, dar duplo clique ou escolher **Abrir** no menu de contexto mostra a página
num visualizador interno ao lado da tabela. **Fechar** esconde o painel e devolve a largura à tabela.
O visualizador aceita apenas HTTP/HTTPS, permite os recursos e redirecionamentos da página e abre
links para outras páginas no navegador padrão. **Abrir no navegador** continua disponível no menu
e no painel. Não há barra de endereço ou histórico; cookies e dados de navegação são temporários.
Abrir e fechar o painel não altera arquivos do projeto nem cria passos de undo.

A coleção `claude` em `vibedeck.json` guarda referências escolhidas pelo usuário: `id`, `title`, `url`,
`kind` (`artifact` ou `doc`), `tags` e `addedAt`. Projetos antigos começam sem itens; o campo vazio é omitido.
A sidebar aparece após o primeiro item; o botão Adicionar do Claude em Links permite começar.
Só aceita URLs do claude.ai. O usuário escolhe o tipo e o título; não há importação automática nem API
para apagar na conta. MCP: `list_claude_items` (filtro `kind`) e `add_claude_item` (`url`, `kind`, `title`, `tags`).

Schemas: https://vibedeck-schema.alanreisanjo.workers.dev/v1/{project,review-group,rule-topic,idea,agent,command,skill,workflow,workflow-run,rule-check}.schema.json

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

No app, a lista de **Docs** oferece **Gerar documentos** quando há Claude Code ou Codex instalado.
A geração usa o provedor ativo somente para leitura, com cancelamento e timeout de 180 segundos por chamada.
A proposta permite editar título e conteúdo, pré-visualizar Markdown, descartar documentos e aceitar todos
ou apenas os selecionados. Nada em `.vibedeck/docs` é gravado antes do aceite. São propostos até 8 documentos;
campos vazios e conteúdos acima de 40.000 caracteres são descartados. O prompt exige referências aos arquivos de origem.
O aceite cria Markdown com `author: ai` no frontmatter e slugs únicos, atualiza a lista e é um único passo de undo.
Os documentos podem ser lidos por `vibedeck docs cat` e MCP `read_doc`; criação com autoria também está disponível
em `vibedeck docs new "Título" --body "Conteúdo" --ai` e MCP `write_doc` (`title`, `content`, `generated: true`).

Ideias, docs, temas de revisão e skills podem estar em diretórios aninhados: `ideas/a/b/x.json`,
`docs/a/b/x.md`, `reviews/a/tema.json`, `skills/a/b/x.json`. A referência é o caminho completo,
com slug único dentro do grupo; slugs simples ambíguos são recusados com os caminhos candidatos.
Projetos planos continuam na raiz, sem migração. Diretórios vazios aparecem na árvore.
O app permite criar, renomear, mover e apagar grupos, arrastar itens ou usar o menu Mover para;
movimentos têm um único undo e preservam seleção/abas por identidade. Sem busca, grupos vazios
permanecem visíveis; com busca, só aparecem caminhos com resultados.
Regras têm `group` opcional dentro do JSON do tópico, sem alterar IDs, aplicabilidade ou checks.
Skills agrupam apenas JSON do VibeDeck, sem exportar/mover arquivos nativos dos provedores;
referências de workflows e próximos passos são atualizadas ao mover, e o undo restaura as originais.
O vínculo da promoção usa `sourceIdea` (UUID), mantendo `promotedTopic` como referência ao tópico.
Anexos novos recebem caminhos relativos à profundidade; links antigos de anexos continuam resolvendo.
CLI: `vibedeck groups list|create|move|rename|remove|move-item <ideas|reviews|docs|skills> ...`.
Apagar grupo não vazio exige `--confirmed`, inclusive itens humanos; no app, confirmação explícita.
MCP: `item_groups` (ações `list`, `create`, `move`, `rename`, `move_item`, `delete`)
(`confirmed: true` para grupos não vazios). Listas JSON de itens incluem `slug` e `group`.
Regras: `vibedeck groups move-rule <id> <grupo>` / `move_rule_to_group`; renomear grupo:
`groups rename-rules <tópico> <origem> <destino>` / `rename_rule_group`.
Criar itens: `--reference a/b/slug` no CLI e `reference` no MCP; docs gerados também aceitam destino.
Caminhos absolutos, `..`, níveis vazios e symlinks que escapem da pasta são recusados.

## Itens de revisão

Cada item de `reviews/*.json` descreve algo a ajustar no projeto
("inativar esse botão", "isso não precisa aparecer agora"):

- `kind`: um dos `reviewKinds` do vibedeck.json (padrão: disable, hide, fix, change, remove, note)
- `status`: open | in_progress | done | wontfix
- `priority`: low | normal | high
- `target` (opcional): `file`, `route`, `component`, `selector` — onde no código/app
- `author`: human | ai

**Resolver** (só no app, sem CLI nem MCP; botão em cada item aberto e no cabeçalho do grupo, com Claude ou Codex
instalado): fluxo pergunta → plano → aceite → execução → check. A IA primeiro lê o código (Read/Grep/Glob; Codex
sem escrita) e devolve perguntas e um plano em JSON validado; você responde e aceita o plano. Sem aceite nada
muda. Depois do aceite a IA pode escrever no projeto aberto, um item por vez; cada item roda o próprio check e só
vai a `done` com `ensureVerified` aprovado. Num grupo só entram itens `open` e `in_progress`. Falha, cancelamento
ou item alterado durante o plano deixam o item como estava; Resolver nunca apaga nem marca `wontfix`. Uma
execução por projeto, com progresso e Cancelar.

## Tópicos de regras

- `paths` vazio → o tópico vale para **toda** tarefa; com globs (`Sources/App/**`, `*.swift`) vale
  quando um arquivo alterado casa.
- `rules[].severity`: `must` (bloqueia) | `should` (aviso).
- Você pode propor regras novas (`add_rule`), mas não apague regras de humanos.

## Testes de regras

Uma regra pode ter um `test`: `{mode: script|manual, command, reason, ruleHash, generatedAt}`.

- `script`: `command` roda na raiz do projeto (shell de login) com `$VIBEDECK_FILES` (arquivos alterados, um
  por linha; vazio = projeto todo), `$VIBEDECK_ROOT` e `$VIBEDECK_RULE_ID`. Exit `0` = cumpre, `77` = não se
  aplica, outro = viola (imprima o motivo). Limite de 120 s. `submit_rule_check` roda o script e usa o
  resultado — a sua resposta para essa regra é ignorada.
- `manual`: a regra não é testável objetivamente; ela só é verificada pela IA sob demanda (passo 4).
  Prefira transformar regras manuais em script sempre que der: script não gasta token.
- Se o texto/detalhes da regra mudarem, o `ruleHash` não bate e o teste fica **desatualizado**: a regra volta a
  ser manual (com aviso no check) até o teste ser regenerado.
- Para gerar/atualizar: escreva `.vibedeck/tests/<tópico>/<id8>.sh` (executável), rode-o e registre com
  `set_rule_test` / `vibedeck rules set-test <id> --command <script>` (ou `--manual --reason "..."`).
  Nunca afrouxe a regra para o script passar. `run_rule_tests` / `vibedeck rules test` roda os scripts sem gravar check.
- Os scripts rodam em paralelo (limite padrão: núcleos da máquina; no app, ajustável em Configurações e
  guardado só na máquina). Scripts que chamam a mesma ferramenta de build (swift, npm/yarn/pnpm, cargo, go,
  gradle, mvn, dotnet, composer, make) rodam um por vez: não dependa de ordem entre scripts nem use caminhos
  temporários fixos (use `mktemp`). Os resultados saem na ordem das regras.

## Ideias

Ideias (`ideas/*.json`) são futuras e **não** são regras ativas: `status` new | exploring | approved |
discarded | done, `body` em markdown, `rules` rascunho e `paths` (globs sugeridos, opcional). `promote_idea`
transforma as regras da ideia em um tópico de regras real (aí passam a valer); os `paths` da ideia viram os
do tópico (ou são somados aos dele, sem remover nenhum). `unpromote_idea` desfaz isso (apaga o tópico,
as regras rascunho ficam na ideia); apagar o tópico de outro jeito também despromove a ideia
(`approved` volta para `exploring`). `readiness` é o veredito da IA no app (Descubra/Verificar) sobre a ideia
estar pronta para implementar; qualquer mudança em título, body, paths ou regras o invalida, e o botão
"Implementar" permite reavaliar ao clicar quando o veredito falta, é negativo ou está desatualizado;
a implementação só é iniciada depois de salvar uma avaliação positiva do conteúdo atual. Registre ideias que surgirem com `add_idea`.
Ao clicar em "Salvar avaliação", um veredito viável em ideia com regras marca o status como `approved`, junto com o `readiness` em um único passo de desfazer. Isso não é promoção: `promotedTopic` continua vazio, nenhum tópico é criado e as regras continuam rascunho. Ideias fechadas ou já promovidas mantêm o status; vereditos não viáveis não alteram o status. Rodar Descubra/Verificar sem salvar não aprova a ideia.
No app, ideias `approved` com avaliação viável atual oferecem **Workflow**, **Execução padrão** e **Cancelar** antes de promover regras ou iniciar a implementação. Sem workflows, só aparecem Execução padrão e Cancelar, sem catálogo. O seletor permite escolher um workflow existente ou adicionar itens do catálogo por seleção explícita. No chat, o modo explícito é respeitado; pedidos sem modo aguardam a escolha. Execução padrão usa `IdeaImplementation.prompt`. Workflows recebem o UUID recuperável da ideia; mudanças de título ou descrição não mudam o vínculo. Havendo execução anterior, **Retomar** preserva o estado e **Reiniciar** começa na primeira etapa. A confirmação relê a avaliação atual no disco. Cancelar não inicia nem promove. CLI e MCP continuam sem a pergunta de modo.
`dependencies` lista UUIDs de outras ideias do projeto que precisam estar `done` antes de implementar esta
(qualquer outro status, ou ideia ausente, bloqueia). Dependentes são derivados, nunca gravados. Edite com
`vibedeck ideas depend|undepend <ideia> <deps…>` ou `update_idea` com `dependencies` (lista completa); o Core
recusa autorreferência, ideia inexistente e ciclos sem gravar nada. `ideas show --json` e `get_idea` trazem
`dependents` e `dependencyBlockers`. Dependências pendentes não impedem a aprovação; bloqueiam só a
implementação (padrão ou workflow, app ou chat), antes de promover, criar run ou chamar o provedor.
No app, "Copiar prompt" copia o pedido de implementação para usar em outra ferramenta, com o tópico
promovido ou as regras rascunho, sem promover a ideia. Funciona mesmo sem provedor de IA e mostra "Copiado".

## Provedores de IA

Registros e workflows são compartilhados entre Claude e Codex. Ao importar ou iniciar uma execução pelo
MCP, informe `provider: "codex"` quando estiver no Codex; pela CLI use `--provider codex`.
Conversas e execuções persistem o provedor e não mudam automaticamente para outro.
No app, ambos os provedores usam o motor do VibeDeck para workflows. Saídas concluídas ficam em `checkpoint` antes de avaliar condições; retomar preserva a etapa, histórico e respostas. Planejar no Codex apresenta o plano para aprovação explícita; Editar projeto permite escrita e mantém as aprovações de comandos.
Agentes, comandos e skills aceitam `providerSettings` (`claude`/`codex`, com `model` e `effort`).
Modelos ou esforços explicitamente escolhidos e incompatíveis interrompem a operação; escolha outro explicitamente. Não há troca automática.
`codex_usage` / `vibedeck usage --provider codex` consulta os limites do Codex sem statusline.

## Agentes

**Kits pré-definidos**: consulte `vibedeck kits list --json` ou `ai_catalog(kind: "kits")`.
Há kits de manutenção de sistema e de desenvolvimento de novas ferramentas, cada um com agente, comando,
skill e workflow. No app, abra "Kits pré-definidos" nas listas ou páginas desses itens; confira o conteúdo,
selecione e confirme "Adicionar selecionados". Abrir o catálogo não grava nada.
Use `vibedeck kits add <ids de kits ou itens…> --ai --json` ou `add_kit(items: ["manutencao"])`.
Um id de kit seleciona todos seus itens. Workflows exigem a seleção explícita das dependências indicadas;
seleção incompleta não cria arquivos. Os itens são cópias comuns, editáveis manualmente ou por IA, sem
vínculo com o catálogo. Adicionar novamente usa slugs únicos, sem sobrescrever, e remapeia as referências
para as novas cópias. No app, toda a adição é um passo de undo/redo e aparece ao vivo.

Agentes (`agents/*.json`) são agentes **do VibeDeck**: `title` (nome), `model`, `prompt` (markdown), `tools` e
`nextSteps` — `{kind: agent|command|skill, ref, note}` apontando para outros agentes/comandos/skills do **VibeDeck**
(nunca do provedor de IA). Os próximos passos formam um fluxo: o próximo atua sobre o resultado do anterior.
`agent_flow` / `vibedeck agents flow <ref>` devolve o JSON do fluxo (prompt + passos encadeados) para orquestrar
a IA. `import_agents` / `vibedeck agents import` traz os agentes do Claude Code (`.claude/agents`); `--provider codex` importa os TOML de `.codex/agents`.

**Criar e editar com IA** (agentes, comandos, skills e workflows): no app, "Criar com IA" (nas listas) e
"Editar com IA" (no detalhe) pedem uma proposta ao provedor ativo (Claude Code ou Codex), só com leitura, e permitem
refinar em sequência; nada é gravado antes do aceite, que é um único passo de undo. Pelo CLI/MCP, quem chama é a IA:
`vibedeck ai item-prompt <tipo> --request "…" [--item <ref>]` / `item_ai_prompt` devolve prompt e schema (sem gravar) e
`vibedeck ai item-apply <tipo> --file proposta.json [--item <ref>]` / `item_ai_apply` valida o JSON e cria (`author=ai`,
slug único, sem sobrescrever) ou substitui o item.

## Comandos

Comandos (`commands/*.json`) são comandos **do VibeDeck**, no formato dos slash commands: `title`, `summary`,
`argumentHint` (o que vai em `$ARGUMENTS`), `model`, `tools`, `prompt` (markdown) e `nextSteps`, com o mesmo
fluxo dos agentes — um agente pode ter um comando como próximo passo e vice-versa. `ref` de um passo `command`
precisa ser um comando existente. `command_flow` / `vibedeck commands flow <ref>` devolve o JSON do fluxo;
`import_commands` / `vibedeck commands import` traz os comandos do Claude Code (`.claude/commands`); `--provider codex` importa prompts legados de `.codex/prompts`.

## Skills

Skills (`skills/*.json`) são skills **do VibeDeck**, no formato do `SKILL.md`: `title`, `summary` (quando usar a
skill — é o que a dispara), `model`, `tools`, `prompt` (as instruções, em markdown) e `nextSteps`, com o mesmo
fluxo dos agentes e comandos. `ref` de um passo `skill` precisa ser uma skill existente. `skill_flow` /
`vibedeck skills flow <ref>` devolve o JSON do fluxo; `import_skills` / `vibedeck skills import` traz as skills do
Claude Code (`.claude/skills/<nome>/SKILL.md`) ou, com `--provider codex`, as skills descobertas pelo Codex.
O caminho do `SKILL.md` importado é preservado para que os recursos de apoio possam ser lidos.

## Workflows

Workflows (`workflows/*.json`) orquestram um fluxo inteiro e podem ser reusados pelo nome: `title`, `summary`,
`input` (o que pedir ao iniciar), `maxSteps` (limite de etapas por ciclo de execução, padrão 25) e
`steps` — cada etapa `{id, kind: agent|command|skill, ref, note, maxVisits, transitions}` roda um
agente/comando/skill do **VibeDeck** (o mesmo pode aparecer mais de uma vez); `maxVisits` limita quantas vezes ela
roda por ciclo. A primeira etapa é o início. `transitions` são `{verdict, when, to}`: depois da etapa, vale primeiro a
de `verdict` igual à última linha do resultado (maiúsculas e acentos não importam), depois a primeira cujo `when`
(linguagem natural) valer, por fim a sem nenhum dos dois ("senão") — inclusive para etapas anteriores (laços);
nenhuma = fim. Os `nextSteps` dos agentes/comandos/skills não valem dentro de um workflow. Monte com
`add_workflow`, `add_workflow_step` e `add_workflow_transition` (ou `vibedeck workflows new|step|route --verdict`).

## Execuções de workflows

Para **executar** um workflow, use `workflow_run_start` / `vibedeck runs start <workflow> --input "..."`. A
execução fica em `runs/<workflow>/<execução>/` (o nome vem da entrada: rodar de novo com a mesma entrada retoma;
uma execução terminada abre um novo ciclo). A pasta guarda também o que as etapas gravam (`$RUN_DIR`).

- **Orquestrador** (o chat): único contato com o usuário. Pede a próxima ação (`workflow_run_next` / `runs next`):
  `run-step` → lança **um subagente** por etapa só com "rode `vibedeck runs step <ref>` e siga"; `ask` → faz as
  perguntas abertas ao usuário e grava com `runs answer`; `decide` → avalia as condições e registra com `--to`;
  `done`/`stop` → relatório. O retorno de cada etapa vai para `runs record --verdict "<última linha>"`.
  `vibedeck runs start ... --prompt` imprime o roteiro completo.
- **Etapa** (subagente): segue o prompt de `runs step`, grava artefatos em `$RUN_DIR` e termina com o veredito na
  última linha. Não fala com o usuário: grava perguntas com `runs ask` e termina com `PERGUNTA`; depois roda de
  novo lendo as respostas.
- Paradas de segurança: `maxSteps`, `maxVisits` e "a etapa voltou para si com o mesmo veredito". Para liberar
  mais uma volta: `runs start <workflow> --input "..." --from <etapa>`.

No painel do Codex, o VibeDeck controla esse ciclo e cada etapa usa uma thread nova com contexto limpo.
Perguntas são apresentadas no painel e gravadas antes de retomar a etapa.

`workflow_flow` / `vibedeck workflows flow <ref>` continua devolvendo o JSON do workflow (sem estado em disco).

## Tags

Docs (frontmatter `tags: [a, b]`), grupos de revisão, tópicos de regras, ideias, agentes, comandos, skills, workflows,
tecnologias da stack e padrões aceitam `tags`.
Use `set_tags` (MCP) ou `vibedeck tag <doc|review|rules|idea|agent|command|skill|workflow|stack|pattern> <ref> <tags...>`.

## Logs

Ações `ui.*` (botões, menus, atalhos, seleções e confirmação de campos) e reações `store.*`, `ai.*`,
`rules.*` ficam em Application Support, fora do projeto, junto com erros e crashes. Campos registram só
Return ou perda de foco, sem conteúdo e sem uma entrada por tecla. `context.control` identifica o controle,
`context.label` traz seu rótulo e `context.action` liga cada ação às suas reações. Gravações incluem arquivo
relativo e nome do undo; mudanças externas incluem `origin=external`. CLI/MCP registram nome e duração em ms.

No app: **Ajuda › Diagnóstico…**, nível **Info**, campo **Id da ação** ou **Filtrar esta ação** no detalhe.
No CLI: `vibedeck logs --level info --since 5m --component app --json`;
`vibedeck logs --level info --action ID --json` mostra uma ação e suas reações.
No MCP: `read_logs` aceita `level` (padrão `info`), `since`, `components`, `action` e `limit`.
Os resources `vibedeck://logs` e `vibedeck://logs/crashes` mantêm seus filtros de aviso/crash.
JSON Lines por dia, com `O_APPEND`, por 14 dias; nunca conteúdo de prompts, documentos, campos ou argumentos.

## Regras gerais para agentes

1. Prefira o CLI (`vibedeck ...`) ou o servidor MCP (`vibedeck mcp`) em vez de editar o JSON à mão.
   Se editar à mão, siga o schema e mantenha ids (UUID) e datas ISO 8601.
2. Itens criados por você devem ter `author: "ai"`.
3. Ao começar um item, marque `in_progress`; ao concluir, `done`. Não apague itens de humanos.
4. Antes de mexer em uma área, leia os itens abertos que apontam para ela.

## Comandos úteis

```sh
vibedeck status                              # resumo do projeto
vibedeck logs --since 24h --json             # erros e falhas recentes (report: texto para issue)
vibedeck stack --json                        # tecnologias de destaque (consulte antes de implementar)
vibedeck stack search postgres | vibedeck stack add postgres --note "17, via Prisma" --ai
vibedeck patterns --json                     # padrões de projeto a seguir (TDD, hexagonal, DDD…)
vibedeck patterns catalog | vibedeck patterns add tdd hexagonal --path 'src/core/**' --ai
vibedeck review list --status open --json    # itens abertos
vibedeck review add "Tela de login" --kind hide "Esconder link de cadastro" --file src/Login.tsx --ai
vibedeck review set <id> --status done       # id completo ou prefixo (>= 4 chars)
vibedeck docs list | vibedeck docs cat <slug>
vibedeck claude list --json                  # coleção curada por projeto (filtro --kind artifact|doc)
vibedeck claude add https://claude.ai/public/artifacts/<id> --kind doc --title "Meu doc"
vibedeck claude remove <id>                  # remove só da coleção, nunca da conta
vibedeck rules for src/Login.tsx --json      # regras de script (manuais só contadas; --manual lista todas)
vibedeck rules check --task "..." --file src/Login.tsx --item <id>   # roda os scripts; manuais ficam pendentes
echo '[{"ruleId":"ab12","verdict":"pass","note":"..."}]' | vibedeck rules check --manual --task "..." --file src/Login.tsx --item <id>
vibedeck rules test src/Login.tsx            # roda os scripts das regras aplicáveis (sem gravar check)
vibedeck rules set-test ab12 --command .vibedeck/tests/geral/ab12cd34.sh   # ou --manual --reason "..." / --clear
vibedeck ideas list | vibedeck ideas new "Modo offline"
vibedeck ideas depend <ideia> <dependencia>... | vibedeck ideas undepend <ideia> <dependencia>...
vibedeck agents list | vibedeck agents next <agente> <proximo> | vibedeck agents flow <agente>
vibedeck commands list | vibedeck agents next <agente> <comando> --kind command | vibedeck commands flow <comando>
vibedeck skills list | vibedeck agents next <agente> <skill> --kind skill | vibedeck skills flow <skill>
vibedeck workflows new "Revisão" && vibedeck workflows step revisao <agente> && vibedeck workflows route revisao <de> <para> --when "..."
vibedeck workflows show revisao | vibedeck workflows flow revisao --input "..."
vibedeck runs start revisao --input "PR 12" | vibedeck runs next revisao/pr-12 | vibedeck runs show revisao/pr-12
```

MCP: `vibedeck mcp install` (registra `vibedeck mcp` no Claude Code)

## Projetos SSH

Na tela inicial, Conectar via SSH permite configurar servidor, porta e usuário ou selecionar um alias.
Use chaves/agente SSH ou senha; guardar no Chaves do macOS exige opção explícita. Confirme a impressão
digital do servidor desconhecido. Chave conhecida alterada bloqueia a conexão até verificar a identidade.

Navegue pelas pastas ou digite um caminho; inicializar exige confirmação. O servidor não precisa ter VibeDeck.
Cada edição confirmada é persistida no cache do destino e pode ser recuperada ao reabrir offline. Há
reconexão automática com intervalos crescentes e opção manual. Conflitos mostram as versões local e remota
e aguardam sua escolha. Fechar a apresentação preserva ambas. Arquivos editados offline e apagados no
servidor são recriados quando não há conflito registrado.

Terminal, regras e IA executam no servidor, na pasta selecionada. Claude Code ou Codex deve estar instalado
e autenticado no servidor; não há instalação, troca de provedor ou execução local automática. Use o terminal
SSH para autenticar. IA e regras aguardam sincronizar pendências e resolver conflitos; o terminal permanece
disponível. O painel distingue desconexão, sincronização, pendências, conflitos e sincronização concluída.
