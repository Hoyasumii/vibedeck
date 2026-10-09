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

## Padrões de projeto — siga ao implementar

`patterns` no `vibedeck.json` lista os padrões de código que o projeto adotou (TDD, arquitetura hexagonal, DDD,
CQRS…), com `note` dizendo como o projeto aplica cada um. Antes de implementar, leia os padrões (`list_patterns` /
`vibedeck patterns --json`) e escreva o código seguindo-os, para manter o projeto consistente.
Cada padrão tem um tópico de regras em `.vibedeck/rules/` (`sourcePattern` aponta para ele; `paths` dá o escopo),
então as regras dele chegam pelo `rules_for` e são cobradas no check como qualquer outra.
Para mudar: `pattern_catalog` / `vibedeck patterns catalog` mostra o catálogo; `add_pattern` / `vibedeck patterns add <ids…> --ai`
(ou `--custom "<nome>" --rule "..."`), `remove_pattern` / `vibedeck patterns remove <id>` (apaga o tópico),
`update_pattern` / `vibedeck patterns note|paths <id> ...`. Apagar o tópico de um padrão retira o padrão.

## Estrutura

```
vibedeck.json                 # declara o projeto: nome, links, stack, padrões (patterns), tipos de revisão (reviewKinds)
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

Schemas: https://vibedeck-schema.alanreisanjo.workers.dev/v1/{project,review-group,rule-topic,idea,agent,command,skill,workflow,workflow-run,rule-check}.schema.json

## Itens de revisão

Cada item de `reviews/*.json` descreve algo a ajustar no projeto
("inativar esse botão", "isso não precisa aparecer agora"):

- `kind`: um dos `reviewKinds` do vibedeck.json (padrão: disable, hide, fix, change, remove, note)
- `status`: open | in_progress | done | wontfix
- `priority`: low | normal | high
- `target` (opcional): `file`, `route`, `component`, `selector` — onde no código/app
- `author`: human | ai

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

## Ideias

Ideias (`ideas/*.json`) são futuras e **não** são regras ativas: `status` new | exploring | approved |
discarded | done, `body` em markdown, `rules` rascunho e `paths` (globs sugeridos, opcional). `promote_idea`
transforma as regras da ideia em um tópico de regras real (aí passam a valer); os `paths` da ideia viram os
do tópico (ou são somados aos dele, sem remover nenhum). `unpromote_idea` desfaz isso (apaga o tópico,
as regras rascunho ficam na ideia); apagar o tópico de outro jeito também despromove a ideia
(`approved` volta para `exploring`). Registre ideias que surgirem com `add_idea`.

## Provedores de IA

Registros e workflows são compartilhados entre Claude e Codex. Ao importar ou iniciar uma execução pelo
MCP, informe `provider: "codex"` quando estiver no Codex; pela CLI use `--provider codex`.
Conversas e execuções persistem o provedor e não mudam automaticamente para outro.
Agentes, comandos e skills aceitam `providerSettings` (`claude`/`codex`, com `model` e `effort`).
Modelos incompatíveis com o provedor usam o modelo da sessão, com aviso. Não passe modelos Claude ao Codex.
`codex_usage` / `vibedeck usage --provider codex` consulta os limites do Codex sem statusline.

## Agentes

Agentes (`agents/*.json`) são agentes **do VibeDeck**: `title` (nome), `model`, `prompt` (markdown), `tools` e
`nextSteps` — `{kind: agent|command|skill, ref, note}` apontando para outros agentes/comandos/skills do **VibeDeck**
(nunca do provedor de IA). Os próximos passos formam um fluxo: o próximo atua sobre o resultado do anterior.
`agent_flow` / `vibedeck agents flow <ref>` devolve o JSON do fluxo (prompt + passos encadeados) para orquestrar
a IA. `import_agents` / `vibedeck agents import` traz os agentes do Claude Code (`.claude/agents`); `--provider codex` importa os TOML de `.codex/agents`.

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

## Sessões na nuvem

Codex: use `provider: "codex"` e `environment` no MCP, ou `--provider codex --env <id>` na CLI.
O ambiente também pode ficar em `codexCloudEnvironment` no projeto.

`start_cloud_session` / `vibedeck cloud start "<tarefa>"` cria uma sessão do Claude Code na nuvem sobre o
GitHub. Ela só é criada se a branch padrão local for **igual** à `origin` (`cloud_check` / `vibedeck cloud check`);
se não for, peça ao usuário para dar push/pull. Alterações não commitadas exigem `allow_dirty`. Só crie
sessões na nuvem quando o usuário pedir.

## Regras gerais para agentes

1. Prefira o CLI (`vibedeck ...`) ou o servidor MCP (`vibedeck mcp`) em vez de editar o JSON à mão.
   Se editar à mão, siga o schema e mantenha ids (UUID) e datas ISO 8601.
2. Itens criados por você devem ter `author: "ai"`.
3. Ao começar um item, marque `in_progress`; ao concluir, `done`. Não apague itens de humanos.
4. Antes de mexer em uma área, leia os itens abertos que apontam para ela.

## Comandos úteis

```sh
vibedeck status                              # resumo do projeto
vibedeck stack --json                        # tecnologias de destaque (consulte antes de implementar)
vibedeck stack search postgres | vibedeck stack add postgres --note "17, via Prisma" --ai
vibedeck patterns --json                     # padrões de projeto a seguir (TDD, hexagonal, DDD…)
vibedeck patterns catalog | vibedeck patterns add tdd hexagonal --path 'src/core/**' --ai
vibedeck review list --status open --json    # itens abertos
vibedeck review add "Tela de login" --kind hide "Esconder link de cadastro" --file src/Login.tsx --ai
vibedeck review set <id> --status done       # id completo ou prefixo (>= 4 chars)
vibedeck docs list | vibedeck docs cat <slug>
vibedeck rules for src/Login.tsx --json      # regras de script (manuais só contadas; --manual lista todas)
vibedeck rules check --task "..." --file src/Login.tsx --item <id>   # roda os scripts; manuais ficam pendentes
echo '[{"ruleId":"ab12","verdict":"pass","note":"..."}]' | vibedeck rules check --manual --task "..." --file src/Login.tsx --item <id>
vibedeck rules test src/Login.tsx            # roda os scripts das regras aplicáveis (sem gravar check)
vibedeck rules set-test ab12 --command .vibedeck/tests/geral/ab12cd34.sh   # ou --manual --reason "..." / --clear
vibedeck ideas list | vibedeck ideas new "Modo offline"
vibedeck agents list | vibedeck agents next <agente> <proximo> | vibedeck agents flow <agente>
vibedeck commands list | vibedeck agents next <agente> <comando> --kind command | vibedeck commands flow <comando>
vibedeck skills list | vibedeck agents next <agente> <skill> --kind skill | vibedeck skills flow <skill>
vibedeck workflows new "Revisão" && vibedeck workflows step revisao <agente> && vibedeck workflows route revisao <de> <para> --when "..."
vibedeck workflows show revisao | vibedeck workflows flow revisao --input "..."
vibedeck runs start revisao --input "PR 12" | vibedeck runs next revisao/pr-12 | vibedeck runs show revisao/pr-12
vibedeck cloud check --json                  # branch local == GitHub? (pré-requisito da nuvem)
```

MCP: `vibedeck mcp install` (registra `vibedeck mcp` no Claude Code)
