# VibeDeck

App macOS nativo (SwiftUI + Liquid Glass) para gerenciar projetos feitos com vibe coding:
links, docs Markdown, **pontos de revisão** ("inativar esse botão", "isso não precisa aparecer agora")
agrupados por tema, **regras** que a IA precisa cumprir antes de dar uma tarefa como concluída e **ideias** futuras. Tudo fica em arquivos dentro do próprio repositório, para a IA ler e escrever também.

## Formato no seu projeto

```
<repo>/
  vibedeck.json              # declara o projeto (nome, links, reviewKinds)
  .vibedeck/
    AGENTS.md                # guia para agentes de IA (gerado)
    docs/<slug>.md
    reviews/<slug>.json      # um grupo/tema por arquivo
    rules/<slug>.json        # um tópico de regras por arquivo (paths = globs de escopo)
    ideas/<slug>.json        # uma ideia por arquivo, com regras rascunho
    agents/<slug>.json       # um agente por arquivo: nome, modelo, prompt e próximos passos
    commands/<slug>.json     # um comando por arquivo: prompt com $ARGUMENTS, argumentos e próximos passos
    skills/<slug>.json       # uma skill por arquivo: descrição (quando usar), instruções e próximos passos
    workflows/<slug>.json    # um workflow por arquivo: etapas (agentes, comandos, skills) e transições condicionais
    runs/<workflow>/<execução>/  # execuções de workflows: run.json (estado) + o que as etapas gravam
    tests/<tópico>/<regra>.sh  # scripts gerados a partir das regras ("Gerar testes")
    checks/*.json            # verificações de regras registradas pelos agentes
    attachments/             # arquivos anexados a docs e ideias (arrastar, colar ou "Anexar")
```

## Regras e ideias

- **Tópico de regras**: lista de comportamentos (`must` bloqueia, `should` só avisa). Sem `paths`, vale
  para toda tarefa; com globs (`Sources/App/**`, `*.tsx`), vale quando um arquivo alterado casa.
- **Fluxo do agente** (exigido pelas instruções do MCP e pelo `AGENTS.md`): `rules_for` com os arquivos
  alterados → verificar cada regra manual → `submit_rule_check` com `pass`/`fail`/`na` para elas (o envio roda
  os scripts das demais). Só conclui com `passed=true`.
- **Testes de regras**: "Gerar testes" (barra do tópico) pede ao Claude, no chat, para transformar cada regra
  num script em `.vibedeck/tests/<tópico>/<regra>.sh` — ou marcá-la como **manual** quando não dá para testar
  objetivamente. Daí em diante o check roda o script (na raiz, com `$VIBEDECK_FILES` = arquivos alterados):
  exit `0` cumpre, `77` não se aplica, outro código viola — o Claude não decide essas regras. Editar o texto ou os
  detalhes de uma regra deixa o teste **desatualizado** (volta a ser manual, com aviso) até "Atualizar testes".
  "Rodar testes" executa os scripts do tópico sem gravar check.
- Item de revisão ligado a regras (campo `rules` ou `target.file` casando um tópico) não vai para
  `done` via CLI/MCP sem check aprovado para o item (`vibedeck review set --force` para humanos).
- **Descubra** (no painel do item de revisão, com o Claude Code instalado): o Claude lê o código só com
  Read/Grep/Glob, sem MCP, e propõe o **Onde** (arquivo, rota, componente, seletor) e tópicos de **Regras**,
  cada um com a justificativa. Nada muda até você aceitar: arquivos inexistentes e tópicos desconhecidos são
  descartados, trocar um campo já preenchido começa desmarcado, tópicos só são adicionados e o aceite é um
  único ⌘Z.
- **Ideias**: brainstorm com status, tags, texto markdown e regras rascunho. "Promover" cria um tópico
  de regras real com essas regras. Apagar esse tópico (no app, no Finder ou com `vibedeck ideas unpromote`)
  despromove a ideia: o vínculo some, "Aprovada" volta para "Explorando" e as regras rascunho ficam.
- **Agentes**: nome, modelo e prompt (markdown) de agentes do VibeDeck. Os **próximos passos** apontam para
  outros agentes, comandos ou skills do VibeDeck e formam um fluxo; `vibedeck agents flow <agente>`
  (ou o botão "Copiar fluxo") gera o JSON que orquestra a IA. "Importar do Claude Code" traz os `.md` de
  `.claude/agents` (projeto e usuário).
- **Comandos**: o mesmo fluxo dos agentes, no formato dos slash commands — prompt (markdown, com `$ARGUMENTS`),
  descrição, argumentos, modelo e próximos passos. Um agente pode ter um comando como próximo passo e vice-versa;
  `vibedeck commands flow <comando>` gera o JSON do fluxo. "Importar do Claude Code" traz os `.md` de
  `.claude/commands` (subpastas viram namespace: `git/commit.md` → `git:commit`).
- **Skills**: o mesmo fluxo dos agentes e comandos, no formato do `SKILL.md` — instruções (markdown), descrição
  (quando usar a skill; é o que a dispara), modelo e próximos passos. Agentes, comandos e skills podem ser próximos
  passos uns dos outros; `vibedeck skills flow <skill>` gera o JSON do fluxo. "Importar do Claude Code" traz o
  `SKILL.md` de cada pasta em `.claude/skills` (projeto e usuário); os arquivos de apoio ficam onde estão.
- **Workflows**: orquestram um fluxo inteiro, com nome, para usar sempre que quiser. Cada **etapa** roda um agente,
  comando ou skill do VibeDeck (o mesmo pode repetir); a primeira é o início. Cada etapa tem **transições**
  avaliadas sobre o resultado: primeiro as de **veredito** ("= APROVADO", a última linha do resultado), depois as
  de **condição** ("se ‹condição›", em linguagem natural), por fim um "senão" opcional — podem voltar a etapas
  anteriores (laços). Quando nenhuma transição vale, o workflow termina; `maxSteps` (padrão 25) e o máximo de vezes
  por etapa (`maxVisits`) evitam laço infinito. Na página do workflow, **Etapas** edita e **Fluxo** mostra o
  diagrama: cada transição é uma seta com o veredito ou a condição, laços (voltas) em laranja à esquerda, saltos à
  direita e "Fim" tracejado onde nenhuma transição vale; passar o mouse numa etapa destaca para onde ela pode ir, e
  o duplo clique abre o agente/comando/skill.
- **Execuções**: "Executar" (com o Claude Code instalado) pede a entrada, cria a execução em
  `.vibedeck/runs/<workflow>/<entrada>/` e faz do chat do Claude o **orquestrador**, como o `/conduzir` do
  claude-kit: cada etapa roda num **subagente** com contexto limpo (que lê o próprio prompt com `vibedeck runs step`),
  o veredito decide a transição (`vibedeck runs record`) e as perguntas das etapas chegam ao chat
  (`runs ask` → `AskUserQuestion` → `runs answer`). O estado fica em disco: executar de novo com a mesma entrada
  retoma de onde parou, e a seção **Execuções** do inspetor mostra o caminho percorrido, as perguntas abertas e os
  botões Continuar/Parar. `vibedeck workflows flow <workflow>` (ou "Copiar JSON") continua gerando o JSON do
  workflow sem estado.
- **Conduzir** (só neste repositório): o fluxo do claude-kit portado para o VibeDeck, com issues do GitHub
  (e o Status do GitHub Projects) no lugar do Plane. Comandos `registrar-task-do-github → viabilizar → planejar →
  criticar → implementar → avaliar → abrir-pull-request` (e `buscar-review` para PR já publicado), agentes
  `viabilizador`, `explorador`, `planejador`, `critico`, `implementador`, `verificador` e `revisor-pr`, e a skill
  `status-no-github-project`. Requer `gh auth refresh -s project`.
- **Tags**: docs (frontmatter `tags: [a, b]`), revisões, regras, ideias, agentes, comandos, skills e workflows. Cada seção da sidebar abre
  uma lista filtrável por texto e por `#tag`.

- **Claude no app**: **Claude** e **Terminal** ficam na sidebar (junto de Links) e abrem no detalhe, como
  qualquer item — inclusive em abas (o Terminal sempre numa aba nova). O item Claude da sidebar (ou ⇧⌘C) abre a página do Claude Code rodando na pasta do
  projeto (`claude -p` em stream-json). Ele responde em streaming, faz perguntas com opções e pede
  permissão antes de editar ou rodar comandos (Permitir, Sempre nesta sessão, Sempre em todas as sessões
  — gravado em `.claude/settings.local.json` — ou Negar). A conversa é retomada ao reabrir a janela.
  O seletor de modo (Normal, Planejar, Aceitar edições, Auto) troca o modo na hora; em Planejar, o plano
  aparece formatado para Aprovar, Aprovar e aceitar edições, Aprovar em modo auto ou Pedir mudanças.
  O campo de mensagem tem o autocomplete do terminal: `/` lista comandos e skills (os do Claude Code,
  `.claude/commands` e `.claude/skills` do projeto e do usuário), `@` lista arquivos do projeto e outras
  conversas, e `!` roda um comando de terminal na pasta do projeto (a saída vai para a conversa e para o
  Claude na próxima mensagem). ↑/↓ navegam, Tab ou ↩ aceitam, Esc fecha.
  **Terminal** (⌃`) abre um terminal interativo de verdade (SwiftTerm), com o seu shell de login na pasta
  do projeto, sempre numa aba nova — cada aba é uma sessão própria ("Terminal", "Terminal 2"…). O shell
  continua rodando ao trocar de aba; fechar a aba encerra o shell, e `exit` no shell fecha a aba. Escolher
  outro item na sidebar com um terminal ativo abre o item ao lado, sem derrubar o terminal. Programas
  interativos chamados com `!` (`vim`, `less`, `top`, `ssh`, REPLs sem script, `git commit` sem `-m`…)
  abrem num terminal novo.
  Sem o Claude Code instalado, as opções de IA não aparecem.

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
| ⌘Z / ⇧⌘Z | Desfazer / refazer (docs têm histórico próprio, sobrevive ao autosave) |
| ⌘E | Alternar editar/ler no doc |
| ⇧⌘N | Focar campo de novo item de revisão |
| ⌥⌘I | Mostrar/ocultar painel do item |
| ⇧⌘C | Abrir o Claude Code |
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
vibedeck tag review tela-de-login ui mvp     # substitui as tags (doc | review | rules | idea | agent | command | skill | workflow)
vibedeck mcp install                         # registra o servidor MCP no Claude Code (--scope local/project/user)
vibedeck usage install                       # liga a statusline do Claude Code ao VibeDeck (mantém a atual encadeada)
vibedeck usage [--json]                      # limite da sessão (5h) e da semana, com horário de reset
vibedeck cloud check [--json]                # a main local é igual à do GitHub?
vibedeck cloud start "Corrigir o login" [--allow-dirty]   # cria uma sessão do Claude Code na nuvem
```

### Sessões na nuvem

O botão de nuvem na página do Claude (ou `vibedeck cloud start`, ou a tool MCP `start_cloud_session`) cria uma
sessão do Claude Code na nuvem (`claude --cloud`) sobre o repositório no GitHub e abre o link no navegador.
A nuvem só vê o GitHub, então antes o VibeDeck dá `git fetch` e compara a branch padrão local com a da `origin`:
se uma estiver atrás da outra (ou se divergirem), ele para e avisa que as branches precisam ser iguais.
Alterações não commitadas só geram um aviso, que precisa ser confirmado (`--allow-dirty` / `allow_dirty`).

### Limites do Claude Code

O rodapé da sidebar mostra quanto da **sessão (5h)** e da **semana** do plano do Claude Code já foi usado e
quando cada uma reinicia. Os números vêm da statusline do Claude Code: `vibedeck usage install` (ou o botão
"Mostrar limites do Claude Code" no app) faz ela rodar `vibedeck usage record`, que grava o uso em
`~/Library/Application Support/VibeDeck/claude-usage.json`. Uma statusline que já existia continua aparecendo
(`--then`), e `vibedeck usage uninstall` a devolve. Só funciona com login de assinatura (Pro/Max); com chave de
API o Claude Code não informa limites. Agentes leem o mesmo dado pela tool MCP `claude_usage`.

## Worker (schemas)

```sh
cd worker && npm install
npm run dev        # http://localhost:8787/v1/project.schema.json
npm run deploy     # depois: scripts/set-schema-url.sh https://vibedeck-schema.<sub>.workers.dev
```
