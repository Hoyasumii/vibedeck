# VibeDeck

<!-- vibedeck:stack:start -->
[![My Skills](https://skill-icons.alanreisanjo.workers.dev/icons?i=swift,apple,workers,ts)](https://skill-icons.alanreisanjo.workers.dev)
<!-- vibedeck:stack:end -->

App macOS nativo (SwiftUI + Liquid Glass) para gerenciar projetos feitos com vibe coding:
links, docs Markdown, **pontos de revisão** ("inativar esse botão", "isso não precisa aparecer agora")
agrupados por tema, **regras** que a IA precisa cumprir antes de dar uma tarefa como concluída e **ideias** futuras. Tudo fica em arquivos dentro do próprio repositório, para a IA ler e escrever também.

## Formato no seu projeto

```
<repo>/
  vibedeck.json              # declara o projeto (nome, links, stack, padrões, reviewKinds)
  .vibedeck/
    AGENTS.md                # guia inicial compacto para IA (gerado)
    guide.md                 # referência completa, consultada por seção (gerada)
    docs/<slug>.md
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
em pt-BR; dá para criar padrões próprios (nome, resumo e uma regra por linha). Cada padrão aceita uma nota
("hexagonal só no Core") e um escopo em globs (vazio = projeto inteiro).

Os padrões ficam em `vibedeck.json` (`patterns`), e cada um cria um tópico de regras `.vibedeck/rules/padrao-<nome>.json`
(com `sourcePattern`): as regras chegam à IA pelo `rules_for` e são cobradas no check e no hook `Stop`, como qualquer
outra. Remover o padrão apaga o tópico; apagar o tópico retira o padrão.

```sh
vibedeck patterns                   # lista (--json para a IA)
vibedeck patterns catalog [texto]   # catálogo embutido
vibedeck patterns add tdd hexagonal --path 'Sources/Core/**' --note "..."
vibedeck patterns add --custom "Feature folders" --rule "Uma pasta por feature"
vibedeck patterns note tdd "Swift Testing"
vibedeck patterns paths hexagonal 'Sources/Core/**'
vibedeck patterns remove tdd
```

No MCP: `list_patterns`, `pattern_catalog`, `add_pattern` (author=ai), `remove_pattern`, `update_pattern` e o
resource `vibedeck://patterns`.

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
- **Descubra nas regras** (na barra do tópico de regras e da ideia, com Claude ou Codex instalado): a IA, só com
  leitura, propõe **globs** e **tags**; depois faz uma **entrevista** (até 4 perguntas por rodada, 3 rodadas, com
  "Gerar com o que já tenho") e sugere regras `must`/`should`. Globs catch-all (`**`, `*`, `**/*`) ou que não
  casam nenhum arquivo são descartados, tags novas começam desmarcadas, regras que duplicam ou conflitam com as
  existentes vêm sinalizadas e desmarcadas, e nada é removido. Na ideia as regras entram como rascunho e os globs
  ficam em `paths`. Cada aceite é um único ⌘Z; editar o tópico/ideia durante a chamada descarta a resposta.
- **Ideias**: brainstorm com status, tags, globs (`paths`), texto markdown e regras rascunho. "Promover" cria um tópico
  de regras real com essas regras e globs (se o tópico já existe, os globs são somados; globs que não casam mais
  nenhum arquivo são avisados antes). Apagar esse tópico (no app, no Finder ou com `vibedeck ideas unpromote`)
  despromove a ideia: o vínculo some, "Aprovada" volta para "Explorando" e as regras rascunho ficam.
- **Agentes**: nome, modelo e prompt (markdown) de agentes do VibeDeck. Os **próximos passos** apontam para
  outros agentes, comandos ou skills do VibeDeck e formam um fluxo; `vibedeck agents flow <agente>`
  (ou o botão "Copiar fluxo") gera o JSON que orquestra a IA. "Importar do Claude Code" traz os `.md` de
  `.claude/agents` (projeto e usuário); "Importar de Codex" traz `.codex/agents/*.toml`.
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
  Claude usa o chat como orquestrador e um subagente por etapa; no Codex, o VibeDeck controla a execução
  e abre uma thread com contexto limpo por etapa. Ambos usam o mesmo motor de vereditos, condições,
  perguntas e limites de visitas. O provedor fica gravado na execução; continuar mantém esse provedor.
  As perguntas das etapas aparecem no painel e suas respostas são registradas antes da retomada.
  `vibedeck workflows flow <workflow>` continua gerando o JSON do workflow sem estado.
- **Conduzir** (só neste repositório): o fluxo do claude-kit portado para o VibeDeck, com issues do GitHub
  (e o Status do GitHub Projects) no lugar do Plane. Comandos `registrar-task-do-github → viabilizar → planejar →
  criticar → implementar → avaliar → abrir-pull-request` (e `buscar-review` para PR já publicado), agentes
  `viabilizador`, `explorador`, `planejador`, `critico`, `implementador`, `verificador` e `revisor-pr`, e a skill
  `status-no-github-project`. Requer `gh auth refresh -s project`.
- **Tags**: docs (frontmatter `tags: [a, b]`), revisões, regras, ideias, agentes, comandos, skills e workflows. Cada seção da sidebar abre
  uma lista filtrável por texto e por `#tag`.

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

Requer macOS 26+ e Xcode 27 (SDK do macOS 27):

```sh
scripts/build-app.sh --install-cli   # build/VibeDeck.app + build/VibeDeck-<versão>.dmg + ~/.local/bin/vibedeck
open build/VibeDeck.app              # ou: open -a build/VibeDeck.app <pasta-do-projeto>
swift test                           # testes do Core
```

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
vibedeck rules for Sources/VibeDeckApp/ProjectWindow.swift --json
echo '[{"ruleId":"<prefixo>","verdict":"pass","note":"..."}]' | vibedeck rules check --task "..." --item <id>
vibedeck rules test Sources/VibeDeckApp/ProjectWindow.swift   # roda os scripts das regras aplicáveis
vibedeck rules set-test <regra> --command .vibedeck/tests/geral/ab12cd34.sh   # ou --manual --reason "..." / --clear
vibedeck hook install                        # liga o hook Stop (portão de regras) neste projeto
vibedeck hook install --agent codex          # o mesmo no Codex (.codex/hooks.json)
vibedeck ideas new "Modo offline" --tags futuro && vibedeck ideas promote modo-offline
vibedeck ideas unpromote modo-offline        # apaga o tópico e despromove a ideia
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
vibedeck cloud check [--json]                # a main local é igual à do GitHub?
vibedeck cloud start "Corrigir o login" [--allow-dirty]   # cria uma sessão do Claude Code na nuvem
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
vibedeck cloud start "Corrigir o login" --provider codex --env <ambiente>
```

O instalador inclui o adaptador de compatibilidade com o SDK Swift MCP 0.12; requer Python 3 e preserva
as demais configurações. `--force` substitui apenas um registro gerenciado pelo VibeDeck.
Os agentes nativos importam `name`, `description`, `model`, `model_reasoning_effort` e
`developer_instructions` de TOML. Outras configurações nativas continuam no arquivo original.
Arquivos inválidos são reportados; registros existentes são preservados salvo `--overwrite`.
As tools MCP de importação e `workflow_run_start` também aceitam `provider: "codex"`.

### Sessões na nuvem

O botão de nuvem no painel IA (ou `vibedeck cloud start`, ou a tool MCP `start_cloud_session`) cria uma
sessão do provedor selecionado sobre o repositório no GitHub e abre o link no navegador. Claude usa
`claude --cloud`; Codex usa `codex cloud exec --env <ambiente> --branch <branch>`. O ID do ambiente
Codex Cloud pode ser salvo em `codexCloudEnvironment` no projeto ou informado pela CLI com `--env`.
A nuvem só vê o GitHub, então antes o VibeDeck dá `git fetch` e compara a branch padrão local com a da `origin`:
se uma estiver atrás da outra (ou se divergirem), ele para e avisa que as branches precisam ser iguais.
Alterações não commitadas só geram um aviso, que precisa ser confirmado (`--allow-dirty` / `allow_dirty`).

O projeto traz um `.mcp.json` com o servidor `vibedeck mcp`. A VM da nuvem é Linux, então o CLI e o MCP (`swift build -c release --product vibedeck`, sem o app SwiftUI) compilam em Linux, e o CI garante isso; o binário precisa estar no `PATH` da VM (por exemplo, pelo script de setup do ambiente).

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
