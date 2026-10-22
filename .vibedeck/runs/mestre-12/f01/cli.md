# Inventário do CLI Swift `vibedeck` (v0.2.0) — para reimplementação em Rust

Fontes: Sources/vibedeck/{CLI,AICommands,ItemGroupCommands,ReorganizeCommands}.swift (+ MCPCommand em MCPServer.swift, pois `Mcp` é subcomando raiz). Análise estática; trechos do Core só para saída/erros.
Legenda: [R]=obrigatório, [O]=opcional. REMOVER = decisão "nuvem removida". EXT = processo/rede externo.

## 0. Convenções globais

- Binário `vibedeck`, `AsyncParsableCommand`, versão `0.2.0` (`--version`, `--help`, `help <x>` do swift-argument-parser). Idioma de help/mensagens: pt-BR.
- **RootOptions** (em quase todos os comandos): `-C, --root <dir>` [O] (default: cwd; `~` expandido). Localiza projeto subindo diretórios até achar `vibedeck.json` (`ProjectStore.find`). Sem achar -> `VibeDeckError.notAProject`: "Nenhum vibedeck.json encontrado em <dir> ou diretórios acima. Rode `vibedeck init`.". Exceções: `init` (sem RootOptions, usa argumento posicional `directory`), `graph`/`ai guide`/`ai catalog`..., `hook start`, `usage *`, `logs path|crashes`, `kits list` (não usam store ou não têm -C).
- Todo `options.store()`: (1) `ProjectStore.locate`, (2) `VDLog.setProject`, (3) `try? refreshAgentsGuideIfNeeded()` — **efeito colateral de disco**: reescreve `.vibedeck/AGENTS.md` e `.vibedeck/guide.md` se diferirem do guia embutido (AgentsGuide.markdown / referenceMarkdown). Erros ignorados. Reorganize (todos) usa `ProjectStore.locate(from: options.startURL)` direto (NÃO atualiza o guia, NÃO chama setProject).
- Wrapper main: configura log (componente `cli`); em sucesso loga `cli.command_completed` (ms); em falha loga `cli.command_failed` (nível warning se `VibeDeckError`, senão error; ignora `ExitCode`, `CleanExit`, help). Logs ficam FORA do projeto (Application Support; ver `logs`).
- **Saída de erro / exit**: erro lançado -> `exit(withError:)` do ArgumentParser: stderr `Error: <localizedDescription>` e exit 1. `ValidationError("x")` -> `Error: x` + exit 64 (EX_USAGE) com texto de usage em erros de parse; ver nota: ValidationError dentro de `run()` imprime `Error: x` e sai com **1** (apenas erros de parse/validate() saem com 64 — confirmar no teste de compat). `ExitCode.failure` = 1 sem mensagem. `ExitCode(status)` repassa código.
- **JSON** (`printJSON`): `VDJSON.encoder` = pretty-printed, **chaves ordenadas (sortedKeys)**, **sem escapar `/`**, datas **ISO-8601** (`2025-01-02T03:04:05Z`, sem fração), sem newline extra além do `print` (um `\n` final). Usa indentação de 2 espaços do JSONEncoder do Foundation (`"key" : value` — NOTE: Foundation pretty-print usa `" : "` com espaço antes e depois dos dois-pontos). Reproduzir exatamente: `{\n  "a" : 1\n}`; array vazio `[\n\n]`, objeto vazio `{\n\n}`.
- `hashtags(tags)`: vazio -> `""`, senão `"  #t1 #t2"` (dois espaços iniciais).
- Prefixo de UUID nas listagens: `uuidString.prefix(8)` (UUID em MAIÚSCULAS, como `UUID.uuidString`).
- Enums de argumento (valores literais aceitos, case-sensitive): ReviewStatus `open|in_progress|done|wontfix`; ReviewPriority `low|normal|high`; RuleSeverity `must|should`; IdeaStatus `new|exploring|approved|discarded|done`; NextStepKind `agent|command|skill`; ClaudeItemKind `artifact|doc`; ItemConcept `ideas|reviews|docs|skills`; AIProvider `claude|codex`; HookAgent `claude|codex`; HookScope `local|project`; MCPScope `local|project|user`; WorkflowRunStatus `running|waiting|done|stopped`; LogLevel `debug|info|warning|error|crash`; SkillIconTheme `dark|light`; Tag.Kind `doc|review|rules|idea|agent|command|skill|workflow|stack|pattern`; ItemDiscover.Kind (ai item-*) `agent|command|skill|workflow` (string manual, erro próprio).
- Opções `parsing: .upToNextOption` (consomem valores até a próxima opção): `--tags`, `--rules`, `--topics`, `--tools`, `--component` (logs).
- Flag `--ai`: grava `author: ai` (default human). `--json`: saída JSON.
- Layout em disco (ProjectStore): `vibedeck.json` (manifesto/Project) e `.vibedeck/{docs(md),reviews,rules,ideas,agents,commands,skills,workflows,checks,tests,runs,attachments}/`, `.vibedeck/AGENTS.md`, `.vibedeck/guide.md`. Escrita via `AtomicFile.write`.

## 1. Árvore de subcomandos (raiz `vibedeck`)

```
vibedeck
 reorganize {prompt, analyze, validate, apply}
 groups {list, create, move, rename, remove, move-item, move-rule, rename-rules}   (struct ItemGroups, commandName "groups")
 kits {list, add}
 graph {export}
 ai {guide, context, catalog, usage, item-prompt, item-apply}
 init
 status
 stack {list*, add, remove, note, move, search, badge}
 patterns {list*, catalog, add, remove, note, paths, move}
 links {list*, add, remove}
 claude {list*, add, remove}
 docs {list*, cat, new, write}
 review {groups, list*, add, set, remove}
 rules {list*, show, new, add, remove, for, test, set-test, check, checks}
 ideas {list*, show, new, set, add-rule, depend, undepend, promote, unpromote}
 agents {list*, show, new, set, next, unnext, flow, import}
 commands {list*, show, new, set, next, unnext, flow, import}
 skills {list*, show, new, set, next, unnext, flow, import}
 workflows {list*, show, new, set, step, unstep, move, visits, route, unroute, flow}
 runs {list*, show, start, next, step, record, ask, questions, answer, stop, delete, orchestrate}
 tag
 hook {status*, stop, start, install, uninstall}
 usage {show*, record, install, uninstall}
 cloud {check*, start}                         -> REMOVER (nuvem)
 logs {list*, report, crashes, path}
 mcp {serve*, install, uninstall}
```
`*` = defaultSubcommand (rodado quando só o grupo é digitado, e as opções do default valem no nível do grupo, ex.: `vibedeck rules --json`).

**Contagem**: 26 subcomandos de 1º nível; **137 comandos folha** (executáveis), dos quais 3 são folhas diretas (init, status, tag); 23 grupos intermediários + raiz = 24 ParsableCommand "contêiner". Total de structs `ParsableCommand/AsyncParsableCommand` de comando = 1 raiz + 26 + 134 aninhados = 161 (grep ≈164 inclui `ParsableArguments` RootOptions/FilterOptions e extensões).
Cloud: 2 folhas REMOVER (cloud check, cloud start) -> **135 folhas após remoção**. Opções/código de nuvem a eliminar também: `--provider`/`Cloud` em `usage show --provider codex` NÃO é nuvem (é Codex local; ver 3.24).

## 2. Comandos — detalhe

Notação de saída: `T:` texto, `J:` JSON (--json), `E:` erros, `D:` efeitos em disco, `X:` externos.

### 2.1 reorganize (AsyncParsableCommand; abstract "Propõe organização com IA; só aplica ações com aceite explícito.")
Core: `ReorganizeDiscover`, `ProjectStore.reorganizeFingerprint/applyReorganization`.
- `reorganize prompt` — `-C`. Sempre JSON: `{"fingerprint": <str>, "prompt": <str>, "schema": <schema>}` (chaves ordenadas; `schema` é objeto JSON schema). D: nenhum (não grava; mas não refresca guia). X: nenhum.
- `reorganize analyze` — `-C`; `--provider <claude|codex>` [R, string]; `--model <s>` [O]; `--effort <s>` [O]. Erro se provider inválido: ValidationError "Use claude ou codex.". Chama `ReorganizeDiscover.analyze(store, provider, settings{model,effort})` (async). Saída: JSON da proposta (printJSON). E: `discoverFailed`("O Claude Code não conseguiu descobrir; nada foi alterado.\n<out>"), `discoverInvalidAnswer` ("O Claude Code respondeu num formato inesperado; nada foi alterado. Tente de novo."), `discoverTimedOut` ("O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo."), `claudeNotInstalled`. X: **spawn de `claude` ou `codex` em modo somente-leitura** (provedor IA). D: nenhum esperado (analisa).
- `reorganize validate` — `-C`; `--file <path|->` [R] (JSON da resposta da IA; `-` = stdin); `--fingerprint <s>` [R]. Saída JSON: proposta validada (`ReorganizeDiscover.parse`). Não grava.
- `reorganize apply` — `-C`; `--file <path>` [R] (proposta validada); `--acceptance <path>` [R] (arquivo JSON, apesar do help dizer "JSON": é CAMINHO de arquivo; chaves `selected` [IDs] e `conflicts` {id-ação -> chave do item mantido}). Saída JSON: recibo (`applyReorganization`). D: **grava** mudanças em ideas/docs/skills/agents/workflows/… conforme ações aceitas (mover/mesclar/criar). E: erros do Core (fingerprint desatualizado etc.).

### 2.2 groups (struct ItemGroups; `ItemConcept` = ideas|reviews|docs|skills)
Core: `ProjectStore.listItemDirectories/createItemDirectory/moveItemDirectory/deleteItemDirectory/moveGroupedItem/moveRuleToGroup/renameRuleGroup`.
- `groups list <concept>` — `--json` (flag sem help). T: um `path` por linha. J: array de `{"path": str}` (ItemDirectory: só campo `path`).
- `groups create <concept> <path>` — T: imprime o retorno de `createItemDirectory` (path normalizado). D: cria diretório em `.vibedeck/<concept>/<path>`.
- `groups move <concept> <from> <to>` — T: "Grupo movido." D: move diretório e itens.
- `groups rename <concept> <path> <name>` — `name` não pode conter `/` (E: `invalidGroupPath(name)`). Calcula pai com `ProjectStore.groupPath(of: path)` e move para `pai/name`. T: "Grupo renomeado."
- `groups remove <concept> <path>` — `--confirmed` flag (apagar inclusive itens humanos). T: "Grupo apagado." E: `groupConfirmationRequired`.
- `groups move-item <concept> <reference> <group>` — `group` "" = raiz. T: imprime o novo caminho (retorno de `moveGroupedItem`).
- `groups move-rule <rule> <group>` — T: "Regra movida."
- `groups rename-rules <topic> <from> <to>` — T: "Grupo de regras movido."
Erros comuns: `groupConflict`, `invalidGroupPath`, `ambiguousReference`, `groupNotFound`.

### 2.3 kits
- `kits list` — sem -C. `--json`. J: `KitCatalog.kits` (catálogo embutido). T: `"<kit.id> · <title> — <summary>"` e para cada item `"  <item.id> · <kind.title>: <item.title>"`.
- `kits add [items...]` — `-C`; `items` [String] default []; `--ai`; `--json`. Core `addKitItems(items, author)`. T: `"<Kind.title>: <slug>"` por item. J: array dos itens adicionados. D: cria agents/commands/skills/workflows em `.vibedeck/`. E: `invalidKitSelection`, `missingKitDependencies` (exige todas as dependências), `kitRestoreConflict`.

### 2.4 graph
- `graph export` — `-C`. Core `ProjectGraph.load(root)`, `GraphHTML.write`. T: "Visualização offline exportada em graphify-out/graph.html". D: **sobrescreve `<root>/graphify-out/graph.html`** (HTML offline autocontido). Lê o grafo (graphify-out/graph.json). Não chama IA nem graphify. E: `VibeDeckError.graph(...)` ("Grafo: ...").

### 2.5 ai
- `ai guide` — sem -C. `--section <int>` [O]; `--json`. Sem seção: imprime `AgentsGuide.index`. Com seção: `AgentsGuide.section(n)`; inexistente -> ValidationError "Seção inexistente.". J: o texto como string JSON (printJSON de String -> `"..."` com escapes).
- `ai context <id>` — `-C`; `--offset <int>=0`; `--limit <int>=4000`; `--json`. `AIContextStore(root).page(id, offset, limit)`. T: `page.text` e, se `nextOffset`, `"\nContinuação: --offset N (total: M caracteres)"`. J: página (text, nextOffset, totalCharacters, …).
- `ai catalog <kind>` — `-C`; kind string: agents|commands|skills|workflows|rules; `--offset=0`; `--limit=20`; `--json`. Core `aiCatalog`. T: `"<ref>: <title>[ — <summary>]"` por item + `"Continuação: --offset N"`. J: página `{items:[{ref,title,summary,...}], nextOffset,...}`.
- `ai usage` — `-C`; `--json`; `--clear`. `AIUsageStore(root)`: `--clear` apaga métricas locais do projeto (sem saída). T por registro: `"<operation> · <Provider.title> · <model|modelo não informado> · tarefa <taskID> · tentativa <attempt> · entrada <in|não informada> · saída <out|não informada> · <status>"`. J: array de registros. D: arquivo de uso de IA do projeto (fora de `.vibedeck/`? local ao projeto; localizar em Core `AIUsageStore`).
- `ai item-prompt <kind>` — `-C`; `--request <s>` [R]; `--item <ref>` [O]. kind em agent|command|skill|workflow, senão ValidationError "Tipo inválido: use agent, command, skill ou workflow.". Saída SEMPRE JSON `{"prompt":..., "schema":...}`. Não grava.
- `ai item-apply <kind>` — `-C`; `--file <path|->` [R]; `--item <ref>` [O]. Valida JSON da IA e cria (author=ai) ou substitui item; imprime o retorno de `itemAIApply` (slug/mensagem). E: mensagens pt-BR do Core, sem gravar quando inválido. D: grava `.vibedeck/{agents,commands,skills,workflows}/…`.

### 2.6 init
`init [directory]` — SEM RootOptions. `directory` [O] (default cwd, `~` expandido), `--name <s>` (default = nome da pasta), `--description <s>`. `ProjectStore.initialize`. T: "Projeto criado em <path>". D: cria `vibedeck.json` (Project{name, description,...}), todos os subdiretórios de `.vibedeck/`, `AGENTS.md` e `guide.md`. E: `alreadyAProject("<dir> já contém um vibedeck.json.")`.

### 2.7 status
`status` — `-C`; `--json`. Core `loadProject, listDocs, listGroups, listTopics, listIdeas, listAgents, listCommands, listSkills, listWorkflows`.
- J: objeto `Summary` com chaves: `root`(str), `project`(Project completo), `docs`[slug], `groups`[{slug,title,open,total}], `ruleTopics`[slug], `ideas`[slug], `agents`[slug], `commands`[slug], `skills`[slug], `workflows`[slug].
- T: linha1 `"<name> — <root>"`; `description` se houver; `Stack: a, b`; `Padrões: a, b`; linha em branco + `"Links: N  Docs: N  Grupos de revisão: N"`; para cada grupo `"  • <title> [<slug>] — <open> aberto(s) de <total>"`; final: `"Tópicos de regras: N (M regra(s))  Ideias: N (K abertas)  Agentes: N  Comandos: N  Skills: N  Workflows: N"` (abertas = status não fechado).

### 2.8 stack (AsyncParsableCommand; default `list`; badge no README)
Core `StackService`, `SkillIcons` (catálogo do Skill Icons — **acesso HTTP**).
- `stack list` — `--json`. J: array de StackItem. T vazio: "Stack vazia. Adicione com `vibedeck stack add <tecnologias…>`."; senão `line(item)` = `"<icon>  <name>[  [<category>]][  — <note>]"`.
- `stack add <icons...>` — `--note <s>`, `--ai`, `--json`. Resolve ids/nomes/aliases no Skill Icons. Saída `report`: J = `StackService.Change` (items + readmeWarning); T = `line` por item e, em stderr, `readmeWarning`. D: grava `vibedeck.json` (stack) + atualiza bloco da stack no `README.md`. E: `unknownStackIcons` (com sugestões, nada alterado), `skillIconsUnavailable`. X: **HTTP (skillicons.dev / catálogo)**.
- `stack remove <icons...>` — `--json`. E: `stackItemNotFound`.
- `stack note <icon> [note=""]` — `--json`. Nota vazia apaga.
- `stack move <icon> <position:Int>` — posição a partir de 0; `--json`.
- `stack search [query]` — `--category <s>`, `--limit <int>=50`, `--json`. J: array de ícones. T: `"✓ "` se já na stack senão `"  "`, + `"<id>  <name>[  [<category>]]"`. X: HTTP catálogo.
- `stack badge` — `--theme <dark|light>` (valor inválido é ignorado -> nil), `--sync`, `--json`. `--sync`: `service.syncReadme()` e, se retornar aviso, ValidationError(aviso). Sem stack: T "Stack vazia." / J `null`. J: SkillBadge (url/markdown/html…). T: `badge.markdown`. D (--sync): regrava bloco no `README.md`. X: HTTP.

### 2.9 patterns (default `list`)
Core `PatternCatalog`, `ProjectStore.addPatterns/addCustomPattern/removePatterns/setPatternNote/setPatternPaths/movePattern/patternTopic`.
Saída comum `report(store,json)`: J = array de `ProjectPattern`; T vazio "Nenhum padrão. Veja `vibedeck patterns catalog` e adicione com `vibedeck patterns add <ids…>`."; senão linha: `"<id>  <name>  [<categoria label>]  (<escopo>; <N regra(s) em <slug>>)"` + `"\n    — <note>"`; escopo = "projeto inteiro" | globs `, `-joined | "sem tópico".
- `patterns list` — `--json`.
- `patterns catalog [query]` — `--json`. J: templates. T: `("✓ "|"  ") + "<id>  <name>  [<cat>]  — <summary>"`.
- `patterns add [patterns...]` — `--custom <name>`, `--summary`, `--rule <s>` (repetível), `--note`, `--path <glob>` (repetível), `--ai`, `--json`. Regras de validação: custom exige >=1 `--rule` ("Padrão personalizado precisa de ao menos uma --rule."); sem custom exige ids ("Informe ids do catálogo ou --custom <nome>."). D: grava `vibedeck.json` (patterns) e cria tópico de regras `.vibedeck/rules/…`. E: `unknownPatterns` (com sugestões).
- `patterns remove <patterns...>` — apaga padrão e tópico de regras. E: `patternNotFound`.
- `patterns note <pattern> [note=""]`.
- `patterns paths <pattern> [globs...]` — sem globs = projeto inteiro.
- `patterns move <pattern> <position>`.
Todos terminam com `report`.

### 2.10 links (default `list`) — grava em `vibedeck.json`
- `links list` — `--json` (array Link). T: `"<id8>  <title>  <url>[  #tags…]"`.
- `links add <url>` — `--title` (default = url), `--tags ...`. Imprime o UUID completo.
- `links remove <id>` — prefixo case-insensitive; remove todos os que casam; E: ValidationError "Link não encontrado: <id>".

### 2.11 claude (coleção de artefatos/docs do Claude; default `list`) — LOCAL, manter
- `claude list` — `--json`, `--kind <artifact|doc>`. T: `"<id8>  [<Artefato|Doc>] <title>  <url>  <addedAt.formatted()>[hashtags]"` (formato de data localizado do Foundation: ATENÇÃO, não determinístico; usar equivalente).
- `claude add <url>` — `--kind` [R]; `--title`; `--tags ...`; `--json`. `addClaudeItem`. Imprime UUID completo (ou J item). E: `invalidClaudeURL`, `ambiguousClaudeItem`. D: `vibedeck.json` (claude[]).
- `claude remove <id>` — id, prefixo (>=4) ou título. E: `claudeItemNotFound`.

### 2.12 docs (default `list`)
- `docs list` — `--json`: array de `{"slug", "value": DocInfo}` (GroupedRecord; DocInfo{slug,title,tags,modified}); ATENÇÃO: confirmar forma exata de `GroupedRecord` no Core (aqui apenas `GroupedRecord(slug:value:)`). T: `"<slug>\t<title>[hashtags]"`.
- `docs cat <slug>` — imprime conteúdo sem newline extra. E: `docNotFound`.
- `docs new <title>` — `--body <s>=""`, `--reference <grupo/slug>`, `--ai`. Imprime slug. `--ai` usa `createGeneratedDoc`. D: `.vibedeck/docs/<slug>.md`.
- `docs write <slug>` — `--text <s>` ou stdin se ausente. Sobrescreve doc.

### 2.13 review (default `list`) — `.vibedeck/reviews/*.json`
- `review groups` — `--json`: array `GroupedRecord(slug, group)`. T: `"<slug>\t<title>\t<open>/<total>[hashtags]"`.
- `review list` — `--group <ref>`, `--status <ReviewStatus>`, `--kind <str>`, `--json`. J: array `{"group": slug, "item": ReviewItem}`. T: por grupo `"\n## <slug>"` e por item `"<id8>  [<status>] (<kind>) <title>[  → <file route component selector joined ' '>]"`.
- `review add <group> <title>` — `--kind=note`, `--details`, `--priority=normal`, `--file`, `--route`, `--component`, `--selector`, `--rules ...`, `--ai`. Valida kind contra `project.reviewKinds` (E: "Kind desconhecido '<k>'. Disponíveis: a, b"). `--rules` resolvidos por `resolveTopicSlug`. Saída: `"<UUID completo>\t<group-slug>"`. D: cria grupo se não existir.
- `review set <id>` — `--status`, `--priority`, `--kind`, `--title`, `--details`, `--rules ...` (substitui), `--force`. Se `--status done` sem `--force` -> `ensureVerified(id)` (E: `rulesNotVerified`). T: `"<id8>  [<status>] <title>"`.
- `review remove <id>`.

### 2.14 rules (default `list`) — `.vibedeck/rules/*.json`, `.vibedeck/checks/`, `.vibedeck/tests/<topic>/<rule>.sh`
printRules: linha `"<indent=2 espaços><id8>  <●|○> <text>[  ✨ se ai][  ⚙ <command>|  ✋ manual|  ⚠ teste desatualizado]"` (● must, ○ should).
- `rules list` — `--json`: array `TopicChecklist{slug, topic…}`. T: `"<slug>\t<title>\t<N> regra(s)\t[global|globs]hashtags"`.
- `rules show <topic>` — `--json`. T: `"<title> [<slug>] — <global|globs>"`, descrição, regras.
- `rules new <title>` — `--description`, `--path <glob>` (repetível, campo `paths`), `--tags ...`. Imprime slug.
- `rules add <topic> <text>` — `--details`, `--should`, `--ai`. Cria tópico se não existe. Saída `"<UUID>\t<slug>"`.
- `rules remove <id>`.
- `rules for [files...]` — `--topics ...`, `--item <id>`, `--manual`, `--json`. Com `--item` soma tópicos do item e seu `target.file`. J: array TopicChecklist (includeManual). T: "Nenhuma regra aplicável." | `"## <title> [<slug>]"` + regras.
- `rules test [files...]` — `--topics ...`, `--item`, `--json`. **Executa scripts** das regras (exit 0 = cumpre, 77 = n/a, outro = viola). Sem args roda todos os tópicos. J: array `RuleTestRunRow`. T: `"<✅|❌|–> [<topic>] <id8> <text>  (exit N)"` e, em falha, saída indentada 4 espaços. **Exit 1** se alguma `must` falhar. T vazio: `Nenhuma regra aplicável tem script. Gere com o botão "Gerar testes" no app.` X: `sh`/script na raiz do projeto.
- `rules set-test <id>` — exatamente um de `--command <s>`, `--manual`, `--clear` (validate(): "Use exatamente um de --command, --manual ou --clear."; erro de parse -> exit 64); `--reason`. T: `"<id8>\t<testState.label>"`. D: `--clear` apaga script em `.vibedeck/tests`.
- `rules check` — `--task <s>` [R]; `--file <p>` (repetível; propriedade `files`); `--topics ...`; `--item`; `--results <json inline>` (padrão stdin só com `--manual`); `--ai`; `--manual`; `--json`. Decodifica `[RuleAnswer]` (`ruleId`, `verdict` pass|fail|na, `note`). Roda scripts; manuais pendentes sem `--manual`. J: check completo. T: `✅ Aprovado (N regra(s), S por script)` | `❌ Reprovado`; `  ✗ <failure>`; `  ⚠ <warning>`; `  ⏭ N regra(s) manual(is) não verificada(s) (use --manual)`. **Exit 1 se reprovado**. D: grava `.vibedeck/checks/<…>.json`. E: `incompleteCheck`.
- `rules checks` — `--topic`, `--limit=20`, `--json`. T: `"<createdAt formatted numeric/short>  <✅|❌>  <task>[  item <id8>]"`.

### 2.15 ideas (default `list`) — `.vibedeck/ideas/*.json`
- `ideas list` — `--status`, `--json` (GroupedRecord slug/idea). T: `"<slug>\t[<status>] <title>  (<N> regra(s))[tags]"`.
- `ideas show <idea>` — `--json` (`ideaDetail`: idea + dependencyBlockers + dependents). T: título — status.label, corpo, "Regras rascunho:" + regras, "Promovida para o tópico: X", "Dependências: uuid, …", "Impedimento: msg", "Dependentes: slug [status], …".
- `ideas new <title>` — `--reference`, `--body`, `--tags ...`, `--ai`. Imprime slug.
- `ideas set <idea>` — `--status`, `--title`, `--body`. T: `"<slug>\t[<status>] <title>"`.
- `ideas add-rule <idea> <text>` — `--should`, `--ai`. Imprime UUID da regra.
- `ideas depend <idea> <dependencies...>` / `ideas undepend …` — T: `"<slug>\t<N> dependência(s)"`. E: `invalidIdeaDependency` ("... Nada foi alterado.").
- `ideas promote <idea>` — imprime retorno de `promoteIdea` (slug do tópico criado); aviso em stderr se globs não casam: "Aviso: globs da ideia que não casam nenhum arquivo foram copiados: a, b". D: cria tópico em `.vibedeck/rules/`; E: `ideaNotImplementable`.
- `ideas unpromote <idea>` — T: "A ideia não estava promovida." | "Tópico removido: <t>" | "Vínculo removido (o tópico já não existia)."

### 2.16 agents / commands / skills (estrutura quase idêntica; default `list`)
Diretórios: `.vibedeck/agents`, `.vibedeck/commands`, `.vibedeck/skills` (skills têm grupos/`--reference`).
- `list` — `--json`. agents J: array de `Agent` (sem slug); commands J: array de `Command`; skills J: array `GroupedRecord(slug, skill)`. T: `"<slug>\t<title>[ <argumentHint> (só commands)]  [<model|herdado>]  → <N> passo(s)[tags]"`.
- `show <ref>` — `--json` (objeto completo). T: `"<title> — modelo: <model|herdado>"`, summary, [commands: `Argumentos: <hint>`], `Ferramentas: a, b`, `"\n<prompt>\n"`, `"→ [<kind>] <ref>[ — <note>]"` por passo.
- `new <title>` — `--model`, `--summary`, `--prompt=""`, `--tools ...`, `--tags ...`, `--ai`; commands: `--argument-hint`; skills: `--reference <grupo/slug>`. Imprime slug.
- `set <ref>` — `--title`, `--model`, `--provider <claude|codex>`, `--effort`, `--summary`, `--prompt`; commands: `--argument-hint`. Semântica: com `--provider`, `--model/--effort` vão para `providerSettings[provider]` (string vazia/whitespace -> remove, `nonEmptyOrNil`); sem `--provider`, `--model` altera `model` legado. `--summary`/`--argument-hint` vazios -> nil; `--prompt` aceita vazio. T: `"<slug>\t<title>"`.
- `next <ref> <target>` — `--kind=agent|command|skill`, `--note`. T: `"<slug>\t<N> passo(s)"`. E: `invalidNextStep`.
- `unnext <ref> <ref2>` — remove passos cujo `ref` ∈ {arg, slug resolvido de agente/comando/skill}. Sem saída.
- `flow <ref>` — imprime JSON de `AgentFlow.json(...)` (compacto? — string já pronta do Core; ver `AgentFlow`), "" se nulo.
- `import` (async; X: lê diretórios, sem processo) — `--provider <claude|codex>=claude`, `--overwrite`, `--dir <path>`, `--ai`. Importa de `.claude/{agents|commands|skills/<n>/SKILL.md}` do projeto e do usuário (para codex, diretórios do Codex via `AIProvider`). Avisos -> stderr; slugs -> stdout um por linha; vazio -> "Nada para importar.". D: grava itens em `.vibedeck/…`.

### 2.17 workflows (default `list`) — `.vibedeck/workflows/*.json`
- `list` — `--json` (array Workflow). T: `"<slug>\t<title>  → <N> etapa(s)[tags]"`.
- `show <wf>` — `--json`. T: `"<title> — até <maxSteps|Workflow.defaultMaxSteps> etapa(s) por execução"`, summary, `Entrada: <input>`, por etapa `"\n<n>. <id> [<kind>] <ref>[  (início)][  (até Nx)][ — note]"` e `"   <i>. <label> → <to>"` ou `"   → fim"`.
- `new <title>` — `--summary`, `--input`, `--max-steps <int>`, `--tags ...`, `--ai`. Imprime slug.
- `set <wf>` — `--title`, `--summary`, `--input`, `--max-steps` (0 = padrão/nil). T `"<slug>\t<title>"`.
- `step <wf> <target>` — `--kind`, `--note`, `--max-visits <int>`. T: `"<slug>\t<step-id>"`.
- `visits <wf> <step> <max>` — 0 = sem limite. T: `"<slug>\t<step>: até Nx|sem limite"`.
- `unstep <wf> <step>` — remove etapa e transições para ela. T: `"<slug>\t<N> etapa(s)"`.
- `move <wf> <step> <position>` (1 = início). T: `"<slug>\t<id> → <id> → …"`.
- `route <wf> <from> <to>` — `--verdict <s>` (casa última linha do resultado), `--when <s>` (condição em linguagem natural); sem nenhum = "senão". T: `"<slug>\t<stepId>: <N> transição(ões)"`.
- `unroute <wf> <from> <index>`. Sem saída.
- `flow <wf>` — `--input <s>`, `--prompt` (flag; prompt completo em vez de só JSON). Saída: `plan.json()` ou `plan.prompt()`.

### 2.18 runs (default `list`) — `.vibedeck/runs/<workflow>/<execução>/` (estado + artefatos)
`<execution>` = `<workflow>/<execução>`, nome ou id (resolve `resolveRunRef`).
`printRunAction(action,json)`: J = WorkflowRunAction (`action` ∈ run-step|ask|decide|done|stop, `step`, `reason`, `candidates`[{label,to}], `questions`[{number,step,question,…}]…); T: `"<action>\t<step|->\t<reason>"` + `"  <label> → <to>"` por candidata + `"  <n>. [<step>] <question>"`.
- `runs list` — `--workflow <ref>`, `--status <running|waiting|done|stopped>`, `--json`: array `{"ref","run"}`. T: `"<ref>\t<status>\t<current|->\t<N> etapa(s)[  ❓<N abertas>]"`.
- `runs show <exec>` — `--json` (WorkflowRun). T: `"<ref> — <status>[ — entrada: <in>]"`, reason, `"<n>. [c<cycle>] <step> → <verdict|—>[ ⇒ <next>| ⇒ fim][  · <summary>]"`, `Próxima: <current>`, `"❓ <n>. [<step>] <q>[ → <answer>|  (aberta)]"`.
- `runs start <workflow>` — `--provider <claude|codex>`, `--input`, `--from <step>`, `--prompt`, `--json`. `startRun`; `--prompt` imprime `WorkflowOrchestration.orchestratorPrompt(ref,title,input,cli: cliInvocation(),provider)`; senão printRunAction. `cliInvocation()` = arg0 absoluto (se contém `/`) ou "vibedeck". D: cria pasta/estado da execução. NÃO executa a IA (o orquestrador externo chama `runs next/step/record`).
- `runs next <exec>` — `--json`.
- `runs step <exec>` (commandName "step") — imprime prompt da etapa atual (`runStepPrompt`).
- `runs record <exec>` — `--verdict`, `--summary`, `--to <step>`, `--nenhuma` (propriedade `noneHolds`; **nome da flag em português**), `--json`.
- `runs ask <exec>` — lê stdin: array JSON de `WorkflowQuestionDraft` `[{question, context, options:[{label,description}], multiple}]` ou um objeto único. Saída: `"Pergunta(s) gravada(s): 1, 2. Termine com a última linha: PERGUNTA"`.
- `runs questions <exec>` — `--open`, `--json`. T: `"<n>. [<step>] <q>[ → <answer>]"` + `"   - <label>[: <desc>]"`.
- `runs answer <exec> <number:Int> <answer>` — `--json`; respostas múltiplas separadas por "; ".
- `runs stop <exec>` — `--reason`. T: `"<execution>\t<status>"` (note: usa o texto digitado, não o ref resolvido).
- `runs delete <exec>` — apaga execução e pasta.
- `runs orchestrate <exec>` — imprime prompt do orquestrador.

### 2.19 tag
`tag <kind> <ref> [tags...]` — `-C`. Substitui tags (sem tags remove). Kinds: doc (`setDocTags` — tags dentro do md), review (grupo), rules, idea, agent, command, skill, workflow, stack (`setStackTags`), pattern (`setPatternTags`). T: "Tags removidas." | "Tags: a, b".

### 2.20 hook (default `status`) — gate de regras no Stop de Claude Code/Codex
Arquivos: claude/local `.claude/settings.local.json`; claude/project `.claude/settings.json`; codex/project `.codex/hooks.json`; codex/local = não existe.
- `hook status` — `-C`, `--json`. J: `{"hooks":[{"agent","scope","file","on"}], "unverified":[UnverifiedChange]}` (3 entradas hooks: claude local, claude project, codex project; ordem agent×scope sobre `allCases`). T: `"<agent> <scope>: ligado|desligado (<path>)"` ; "Nenhuma alteração pendente de check." ou texto de `stopGateReason`. X: `git` (workingTreeChanges).
- `hook stop` — `-C`; `--max-blocks <int>=3`. Lê JSON do agente em stdin (`session_id`, `transcript_path` (pode ser null), `cwd`). Começa em `cwd` se `-C` ausente. Fora de projeto: retorna silencioso (exit 0). "Início de sessão" = creation date do transcript, senão do arquivo `$TMPDIR/vibedeck-start-<sid>`, senão distantPast. Contador em `$TMPDIR/vibedeck-count-<sid|sem-sessao>`. Saída stdout (JSON compacto via JSONSerialization `.withoutEscapingSlashes`, chaves em ordem de dicionário): bloqueio `{"decision":"block","reason":"<stopGateReason>"}`; após `max-blocks` bloqueios seguidos libera: `{"systemMessage":"⚠️ VibeDeck: o agente parou sem check de regras aprovado para: a, b"}` e remove contador. Sem pendências: remove contador, sem saída. X: **git** (arquivos alterados). Exit 0 sempre (bloqueio é via JSON).
- `hook start` — sem -C. Lê stdin; se `session_id` presente, cria arquivo vazio `$TMPDIR/vibedeck-start-<sid>` se não existir. Sem saída.
- `hook install` — `-C`; `-a/--agent <claude|codex>=claude`; `-s/--scope <local|project>` (default local p/ claude, project p/ codex). Codex+local: ValidationError "O Codex não tem um arquivo de hooks só seu por projeto. Use --scope project (.codex/hooks.json).". Comando registrado: `vibedeck` (PATH) se scope=project, senão caminho absoluto de `vibedeckExecutablePath()`. Codex também registra hook SessionStart. T: "Hook ligado em <path>." (+ codex: "No Codex, aprove o hook com /hooks antes da próxima resposta (hooks novos só rodam depois de aprovados)."). D: edita o JSON de settings (`ClaudeCode.installStopHook`; mantém demais chaves; marcador do comando contém "hook stop").
- `hook uninstall` — mesmas opções; T: "Hook do VibeDeck removido de <path>."; codex+local: ValidationError "O Codex só tem o escopo project (.codex/hooks.json)."

### 2.21 usage (default `show`) — limites do Claude Code (global, não é do projeto)
- `usage show` (async) — `--json`; `--provider <claude|codex>=claude`. claude: lê último uso gravado pela statusline (`ClaudeCode.loadUsage()`, arquivo em Application Support/ ~/.claude); nenhum -> ValidationError "Nenhum uso registrado ainda. Rode `vibedeck usage install` e use o Claude Code.". J: objeto usage. T: `usage.summary()` + `"Atualizado em <data abreviada/hora curta>"`. codex: `CodexQueries.limits(root: cwd)` (X: **spawn `codex`** (app-server) para obter rate limits); J resultado; T `"<id>: <N>% · <min> min"` por limite.
- `usage record` — sem -C. `--then <shell cmd>`. Lê JSON da statusline do stdin, grava uso (`ClaudeCode.recordUsage`, erros ignorados). Com `--then`: executa `/bin/sh -c <then>` passando o mesmo stdin e deixando a saída dele aparecer (aguarda). Sem `--then`: imprime `usage.summary()`.
- `usage install` — grava `statusLine` em `~/.claude/settings.json` apontando para `vibedeck usage record [--then <anterior>]` com `vibedeckExecutablePath()`. T: "Statusline ligada em <settings path>. O uso aparece depois da próxima resposta do Claude Code." E: `invalidStatusLine`, `invalidClaudeSettings`.
- `usage uninstall` — restaura anterior. T: "Statusline do VibeDeck removida de <path>."

### 2.22 cloud — REMOVER (nuvem)
- `cloud check` (default) — `--json`; `CloudSession.check` (git remoto GitHub). Exit 1 se `sync.blocked`.
- `cloud start <description>` — `--provider`, `--env/environment`, `--allow-dirty`, `--json`. Chama `claude --remote`/codex cloud. Remover totalmente; remover também `VibeDeckError.cloudNotSynced/cloudDirty/cloudSessionFailed`.

### 2.23 logs (default `list`) — logs fora do projeto (Application Support); componentes: app, cli, mcp, core, rules, ai, hook
FilterOptions: `-C`; `--since <s>="24h"` (30m/24h/7d; E: `invalidLogFilter`); `--level <LogLevel>=warning`; `--component ...` (upToNextOption, lista); `--all-projects`; `--search <s>`; `--action <s>`; `--limit <int>=100`. Projeto atual = `locate(from: startURL)?.root` (se não achar, sem filtro de projeto).
- `logs list` — `--json`. T vazio: "Nenhuma entrada no período."; senão `entry.line` (mais recente primeiro). J: array de entradas.
- `logs report` — texto do mais antigo ao mais novo, header `"Relatório de diagnóstico do VibeDeck 0.2.0"` (terminator "").
- `logs crashes` — `--since="14d"` (sem -C), `--json`; nível crash. Vazio: "Nenhum crash registrado no período."
- `logs path` — imprime diretório dos logs (`LogStore.default.dir`).

### 2.24 mcp (default `serve`) — ver seção 4
- `mcp serve` — `-C`. `mcp install` — `-C`, `-s/--scope <local|project|user>`, `--provider <claude|codex>=claude`, `--name <s>="vibedeck"`, `--force`. `mcp uninstall` — `-C`, `-s/--scope`, `--provider`, `--name`.

## 3. Dependências externas por comando

Processos / rede (EXT):
- `claude` CLI: `reorganize analyze --provider claude`; `mcp install|uninstall` (provider claude: `/usr/bin/env claude mcp add|remove ...`); `cloud *` (REMOVER). `runs start --provider` apenas registra o provider (orquestrador externo executa).
- `codex` CLI: `reorganize analyze --provider codex`; `usage show --provider codex` (CodexQueries.limits); `mcp install|uninstall --provider codex` (CodexMCP escreve config do Codex: `.codex/config.toml` (project) ou `~/.codex/config.toml` (user) — via arquivo ou `codex mcp`; confirmar no Core).
- `git`: `hook status`, `hook stop` (workingTreeChanges), possivelmente `rules check/test --item` (não; usam só arquivos). `cloud *`.
- `sh`/`/bin/sh -c`: `rules test`, `rules check` (scripts de regras, cwd = raiz), `usage record --then`.
- HTTP (Skill Icons): `stack add|search|badge`.
- ssh: nenhum comando destes 4 arquivos usa `ssh` diretamente (existe `VibeDeckError.ssh` / `RemoteExecution` no Core, usado pelo app); `graphify`: nenhum comando chama o binário — `graph export` só lê graphify-out/graph.json e escreve graph.html.

Dependem de provedor de IA / processo externo de IA: `reorganize analyze` (claude|codex), `usage show --provider codex` (codex), `mcp install|uninstall` (claude|codex CLI), `cloud *` (REMOVER). `ai item-prompt/item-apply`, `reorganize prompt|validate|apply`, `ai *`, `runs *` NÃO chamam IA (apenas produzem/consomem prompts e JSON para uma IA externa).
Dependem de git: `hook status|stop`. Dependem de shell: `rules test|check`, `usage record --then`. Dependem de rede: `stack add|search|badge`.
**Puramente locais** (somente arquivos do projeto): init, status, kits *, graph export, ai guide|context|catalog|usage|item-prompt|item-apply, reorganize prompt|validate|apply, groups *, links *, claude *, docs *, review *, rules list|show|new|add|remove|for|set-test|checks, ideas *, agents/commands/skills * (inclui `import`: lê diretórios locais), workflows *, runs *, tag, patterns *, stack list|remove|note|move (mas add/remove/note/move atualizam README; remove/note/move não usam rede), hook start|install|uninstall, usage install|uninstall|show(claude)|record (sem --then), logs *, mcp serve.

## 4. Como o `vibedeck mcp` é iniciado

- Comando: `vibedeck mcp` (= `vibedeck mcp serve`; serve é o `defaultSubcommand`). Flags: apenas `-C/--root <dir>`. Servidor MCP por **stdio** (transporte `SerializedStdioTransport`), nome `vibedeck`, versão `0.2.0`; capabilities: `resources{subscribe:false, listChanged:false}`, `tools{listChanged:false}`; `instructions` = texto fixo pt-BR (MCPHandler.instructions(root)). Handlers: `tools/list` (descrição ausente -> ""), `tools/call` (sucesso -> content text, isError false; erro -> content text = `localizedDescription`, isError true; `VibeDeckError`/`MCPError` logados como warning, outros como error; só nome da tool e ms são logados), `resources/list`, `resources/read`. Inicialização: `VDLog.configure(.mcp)`, `store()` (que atualiza AGENTS.md/guide.md), `LogStore.default.prune()`. Falha fora de projeto (sem vibedeck.json acima do cwd/`-C`) com `notAProject` — por isso o escopo `user` "falha em pastas sem vibedeck.json".
- Registro no cliente (`mcp install`):
  - Claude: `env claude mcp add <name> -s <scope> -- <executable> mcp` com cwd = raiz do projeto; `<executable>` = `vibedeck` (do PATH) se scope=project (grava `.mcp.json` versionado), senão caminho absoluto resolvido (`vibedeckExecutablePath`: arg0 se contém `/`, senão primeiro executável no PATH, senão binário atual). `--force` roda antes `claude mcp remove <name> -s <scope>` (ignora o status). Falha: stderr "`claude mcp add` falhou. Se já existe um servidor \"<name>\", use --force." e exit com o status do claude. Sucesso: "Reinicie o Claude Code (ou use /mcp) para carregar as tools do VibeDeck." Se `claude` não executa: stderr "Não foi possível executar `claude`: <erro>" exit 1.
  - Codex: escopos project|user (padrão project; local -> ValidationError "Codex suporta os escopos project ou user."); `CodexMCP.install(root, cli, name, user, force)`; T: "MCP instalado no Codex (<scope>). Reinicie o cliente para carregar as tools."
  - Padrão de escopo: local (claude), project (codex).
- O servidor expõe dezenas de tools (MCPHandler.tools, ~1700 linhas em MCPServer.swift): escopo de outra tarefa (F-MCP); contrato guardado por `scripts/mcp-contract.py`.

## 5. Peculiaridades de compatibilidade (resumo)

1. JSON do Foundation: `sortedKeys`, `prettyPrinted` com `" : "`, sem escapar `/`, datas ISO-8601 sem frações; `printJSON` de `String` gera string JSON escapada; `[:]` vazio -> `{\n\n}`.
2. UUIDs em maiúsculas; prefixos de 8 chars nas listagens; resolução de referências por slug/id/prefixo(>=4)/título.
3. Flags com nomes não óbvios: `--nenhuma` (runs record), `--file` repetível mapeia para `files` em `rules check`; `--path` repetível mapeia para `paths` em `rules new`; `-s/--scope` e `-a/--agent` têm atalho curto; `-C` é atalho curto customizado de `--root`; `--env` em cloud (removido).
4. Opções `upToNextOption`: ao reimplementar com clap, usar `num_args(1..)` e cuidado com a posição de argumentos posicionais após elas.
5. `defaultSubcommand`: `rules`, `ideas`, `agents`, `commands`, `skills`, `workflows`, `runs`, `docs`, `review`, `links`, `claude`, `stack`, `patterns`, `hook`(status), `usage`(show), `logs`(list), `mcp`(serve), `cloud`(check) — com flags do default aceitas no nível do grupo.
6. `reorganize apply --acceptance` recebe CAMINHO (help diz JSON). `reorganize *` nunca refresca AGENTS.md.
7. `hook stop` exit sempre 0; bloqueio = JSON no stdout; estado em `$TMPDIR/vibedeck-{start,count}-<session>`.
8. `rules test`/`rules check`: exit 1 quando falha de regra `must`/check reprovado; `rules check` imprime ícones ✅❌⚠⏭ (UTF-8).
9. Mensagens de erro em pt-BR via `VibeDeckError.errorDescription`; stderr `Error: …`.
10. `Set` (structs) sombreia `Swift.Set` — irrelevante para Rust.
