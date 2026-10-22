# F01 — Inventário do servidor MCP Swift (`vibedeck mcp`) para port em Rust

Fonte: `Sources/vibedeck/MCPServer.swift` (L = linha), `SerializedStdioTransport.swift`, `Tests/Fixtures/mcp-contract.json`, `mcp-budget-baseline.json`, `scripts/mcp-contract.py`. Análise estática.
Convenções: `store` = `ProjectStore(root)` (Core); `json(x)` = `VDJSON.encoder` (pretty-printed, sortedKeys, withoutEscapingSlashes, datas ISO8601, SEM newline final) -> string no único bloco `content[0].text`. `compact` = `VDJSON.compactEncoder` (uma linha). Dados em `.vibedeck/{docs,reviews,rules,ideas,agents,commands,skills,workflows,checks,runs,attachments}` + `vibedeck.json`; escrita via `AtomicFile.write`.

## 0. Achados que mudam o escopo

1. **Fixture desatualizada**: `mcp-contract.json` tem 85 tools; o código tem **99** (L257-723). 14 só no código (NÃO estão no contrato): `add_kit, read_logs, export_graph, item_groups, move_rule_to_group, rename_rule_group, list_claude_items, add_claude_item, reorganize_prompt, reorganize_analyze, reorganize_validate, reorganize_apply, item_ai_prompt, item_ai_apply`. Contrato 85 ⊂ código (nenhuma só no contrato). Seção 4 mapeia as 85 + as 14.
2. Removendo `cloud_check` e `start_cloud_session` (contrato): ficam 83 do contrato; 97 no total se portar as 14 extras. Recomendo portar as 14 (já são API pública do servidor atual); decisão do mestre.
3. `scripts/mcp-contract.py check`: compat apenas aditiva (tool/param/type/enum/required não podem sumir; remover as 2 de nuvem fará `tool removida` -> **atualizar fixture/snapshot** no port). Orçamento: `tools` JSON <= 70% de 42434 (=29703 chars), `instructions` <= 1200 chars (baseline antigo 2803), não conter "Trabalhe por escopo", conter `rules_for, submit_rule_check, passed=true, verify_manual, AGENTS.md`. O texto atual das instructions (~1000 chars) respeita.
4. Descrições de tools: **não copiadas** (pedido). Estão inline em `Tool(name:..., description:...)`, L257-723, a linha de cada tool é dada abaixo. `description: nil` vira `""` no tools/list (L140). Regra de omitir descrição de parâmetro: `schema()` L197-213 só emite `description` do parâmetro se len>=40 ou casa a regex L203 (portar a função inteira para obter o mesmo JSON/orçamento; descrições nos dicts `props` L257-723).

## 1. Protocolo / handshake (swift-sdk 0.12.1, `modelcontextprotocol/swift-sdk`)

- `Server(name:"vibedeck", version: VibeDeckCLI.configuration.version, instructions:..., capabilities:)` L129-134.
- serverInfo: `{name:"vibedeck", version:<versão CLI>}`.
- capabilities: `resources:{subscribe:false, listChanged:false}`, `tools:{listChanged:false}`. Sem `prompts`, `logging`, `completions`. **Não há prompts MCP.**
- protocolVersion: negociada pelo swift-sdk (cliente `2024-11-05` no script). Comportamento exato (eco da versão do cliente se suportada, senão a mais nova do SDK) vem do SDK, não está no repo -> verificar (dúvida 1). Sugestão Rust: ecoar a do cliente se em {2024-11-05, 2025-03-26, 2025-06-18}, senão a mais nova.
- Métodos tratados: `initialize`, `ping` (SDK), `tools/list` (L137), `tools/call` (L144), `resources/list` (L160, `nextCursor:nil`), `resources/read` (L161, retorna `contents:[1]`). `notifications/initialized` aceito. Demais -> methodNotFound do SDK (-32601).
- tools/list devolve todas, sem paginação; cada Tool com `name, title?, description(string), inputSchema, annotations?(readOnlyHint)`; sem outputSchema.
- Start de `serve`: `VDJSON`/log configure(component .mcp), `store = options.store()` (acha `vibedeck.json` subindo diretórios; falha se não achar: "Nenhum vibedeck.json encontrado em <p> ou diretórios acima. Rode `vibedeck init`."), `try? store.refreshAgentsGuideIfNeeded()` (reescreve `.vibedeck/AGENTS.md` e `.vibedeck/guide.md` se diferirem do embutido -> **efeito em disco no startup**), `LogStore.default.prune()`.
- `vibedeck mcp` default subcomando = `serve`; `install/uninstall` (L52-114) rodam `claude mcp add/remove -s <scope> -- <exe> mcp` (processo externo `claude` via `/usr/bin/env`) ou `CodexMCP.install/uninstall` (escreve config do Codex). Fora do escopo do servidor, mas fazem parte do comando.

### Texto exato das `instructions` (L172-189; `<root>` = `store.root.path`; indentação de 8 espaços do literal removida; linhas "   (…)" têm 3 espaços de continuação)

```
Projeto VibeDeck em <root>.

REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras.
Antes de dizer que terminou qualquer alteração:
1. chame rules_for com os arquivos que você alterou (e review_item, se houver);
2. chame submit_rule_check (results=[]): ele roda os scripts das regras sozinho; as manuais ficam pending;
3. se passed=false, corrija e envie outro check. Só conclua com passed=true, avisando os warnings
   ("should") e quantas manuais ficaram sem verificar;
4. manuais só quando o usuário pedir: rules_for include_manual=true e submit_rule_check
   verify_manual=true respondendo pass/fail/na para TODAS, com evidência.
Antes de implementar: itens de revisão abertos da área, list_stack e list_patterns. Registros criados por você são author=ai.
Ideias que surgirem: add_idea (não são regras ativas).
Referências aceitam slug, id (ou prefixo >= 4) ou título.
Guia: .vibedeck/AGENTS.md (leia antes). Detalhes: ai_guide.
```
(sem newline final; Swift multiline remove o último `\n`.)

## 2. Transporte (stdio) — `SerializedStdioTransport.swift`

- Ator que embrulha `StdioTransport` do SDK (JSON-RPC **newline-delimited**: uma mensagem JSON por linha em stdin/stdout, sem Content-Length; o script de contrato escreve `json.dumps(m)+"\n"` e lê por linha).
- Serialização de saída: `send` usa um mutex FIFO (`sending` + fila de continuations) para que uma resposta grande (tools/list ~42KB) não seja intercalada com outra quando o pipe não-bloqueante enche. **Requisito Rust**: um único escritor, mensagem inteira + `\n` atômica; várias requisições podem estar em voo (handlers async concorrentes), respostas em qualquer ordem, casadas por `id`.
- `send` faz `Task.checkCancellation()` antes de escrever; cancelamento = Task cancelada, mensagem não enviada (sem tratamento de `notifications/cancelled` próprio no repo; é do SDK — dúvida 2).
- Entrada: `receive()` repassa cada linha (Data) ao Server. Erro do reader encerra o stream.
- EOF em stdin: o stream termina -> `server.waitUntilCompleted()` retorna -> processo sai com 0 (script: "The server stops at EOF"). Mantém-se vivo enquanto stdin aberto.
- stderr: o transporte não escreve nada (logger `SwiftLogNoOpLogHandler`). Logs do servidor vão ao `LogStore.default` (arquivo, via `VDLog`), nunca ao stdout; stderr livre/vazio (script usa DEVNULL). Em `tools/call` registra só `tool` e `ms` (nunca argumentos): `mcp.tool_called` info; falha: warning se erro "esperado" (`VibeDeckError` ou `MCPError`), error caso contrário (`errorType`).
- Notificações (sem `id`) não geram resposta.

## 3. Semântica comum de `tools/call` (L144-159, 728-761)

- Sucesso: `{content:[{type:"text", text:<string>}], isError:false}`. **Nunca** `structuredContent`. O texto é: JSON pretty (`json()`), JSON compacto (só `rules_for`/`read_logs`? ver tabela), ou string livre em português.
- Falha de qualquer tipo (inclui tool desconhecida, params inválidos, erros do Core, I/O): **resultado normal** com `isError:true` e `content:[{type:"text", text:error.localizedDescription}]` — NÃO é erro JSON-RPC. Mensagens de `VibeDeckError` são texto fixo em PT (ProjectStore.swift L60-124, copiar `errorDescription` literal). `MCPError.invalidParams("X")`/`.methodNotFound("Tool desconhecida: <name>")` -> localizedDescription do SDK (provavelmente `"Invalid params: X"` / `"Method not found: ..."`; **verificar no SDK 0.12.1**, dúvida 3). Erros de decode Foundation/outros: descrição do erro Swift (não reproduzível fielmente).
- Helpers de argumentos (L729-761), portar exatamente:
  - `str(k)`: só string; **string vazia = ausente**.
  - `req(k)`: str ou erro `Parâmetro obrigatório: <k>`.
  - `list(k)`: array JSON (itens string, descarta vazios) OU string contendo JSON-array OU string separada por vírgula (trim, descarta vazios); outro tipo -> nil.
  - `int(k)`: inteiro JSON, ou double truncado, ou string numérica. (Mas `ai_guide.section`, `ai_catalog.offset/limit`, `ai_context.offset/limit` usam `.intValue` estrito; `read_logs.limit` usa `int`.)
  - `severity()`: ausente -> `must`; senão `must|should` ou `Severidade inválida: <s>`.
  - `selectedProvider()`: ausente -> `claude`; senão `claude|codex` ou `Provedor inválido: <v>`.
  - `provider_settings`: objeto `{claude|codex:{model,effort}}` decodificado como `[String:AIProviderSettings]`; chave desconhecida -> `Provedor inválido em provider_settings`.
- Bools: `args[k]?.boolValue` (não aceita string "true").
- Nenhuma validação de schema do inputSchema pelo servidor (enums só informativos; ex.: status inválido em `list_review_items` é ignorado silenciosamente via `flatMap(init(rawValue:))`).

## 4. Tools por área

Legenda: **[EXT]** depende de processo externo/rede. **[DEL]** removida (nuvem). **[+]** só no código (fora do contrato de 85). RO = `readOnlyHint:true`. "L" = linha da definição (descrição lá). Efeito disco: W = escreve; R = só lê. Todos os resultados são `content[0].text`.

### 4.1 Projeto / links / Claude items / grafo / logs
| tool (L) | Core | resultado | erros/efeitos |
|---|---|---|---|
| `get_project` (276, RO) | `listGroups`, `loadProject`, `listDocs` | json `{root, project:<Project>, docs:[slug], groups:[{slug,title,open:"n",total:"n"}]}` (n como STRING) | R |
| `add_link` (328) | `updateProject{links.append}` | json `Link{title(=url se vazio), url, tags}`; `tags` aqui é STRING via `list()` (aceita CSV) | W `vibedeck.json`; sem validação de URL |
| `list_claude_items` [+] (335,RO) | `loadProject().claude` filtrado por kind | json array `ClaudeItem` | kind inválido: `Tipo inválido: use artifact ou doc.` |
| `add_claude_item` [+] (338) | `store.addClaudeItem(url,kind,title,tags)` | json do item | `VibeDeckError.invalidClaudeURL`/ambíguo; W `vibedeck.json` |
| `export_graph` [+] (275) | `ProjectGraph.load`, `GraphHTML.write` | texto `Visualização offline exportada em graphify-out/graph.html` | W `<root>/graphify-out/graph.html` (lê grafo de graphify-out) |
| `read_logs` [+] (259,RO) | `LogFilter.parse*`, `LogStore.default.entries` | json array; defaults since=24h, level=info, limit 200 clamp 1..2000; filtra `project`=root | `invalidLogFilter` |
| `set_tags` (714) | por kind: `setDocTags`, `updateGroup`, `updateTopic`, `updateIdea`, `updateAgent/Command/Skill/Workflow`, `setStackTags`, `setPatternTags` | texto `Tags removidas.` ou `Tags: a, b` | kind inválido `Tipo inválido: <x>`; W no registro |
| `add_kit` [+] (257) | `store.addKitItems(items, author:.ai)` | json | `invalidKitSelection`, `missingKitDependencies`, `kitRestoreConflict`; W (arquivos de kit) |

### 4.2 Docs
| `list_docs` (285,RO) | `listDocs` | json `[{group,slug,title,tags}]` (`group=groupPath(of:slug)`) | R |
| `read_doc` (287,RO) | `readDoc(slug)` | **texto markdown cru** | `Doc não encontrado: <s>` |
| `write_doc` (289) | `createGeneratedDoc(title,body,reference)` se `generated=true` (-> `Criado: <slug>`); senão se `slug` -> `writeDoc` (`Salvo: <slug>`); senão `createDoc(title,reference)`+`writeDoc` (`Criado: <slug>`) | texto | `content` obrigatório; `title` exigido nos ramos de criação; W `.vibedeck/docs/<slug>.md` |

### 4.3 Revisões
| `list_review_groups` (296,RO) | `listGroups` | json `[{group,slug,title,description,tags,open,total}]` | R |
| `list_review_items` (298,RO) | `listGroups`, `resolveGroupSlug` | json `[{group:<slug>, item:<ReviewItem>}]`; filtros group/status/kind | grupo inexistente -> `Grupo de revisão não encontrado` |
| `add_review_item` (305) | `loadProject().reviewKinds`, `resolveTopicSlug` por regra, `addItem(item,toGroup)` author=ai, prioridade default `normal`, target{file,route,component,selector} | json `{group:<slug>, item}` | kind fora de `reviewKinds`: `Kind desconhecido '<k>'. Disponíveis: a, b`; W `.vibedeck/reviews/<g>.json` (cria grupo) |
| `update_review_item` (318) | `updateItem(id){...}`; se status=done -> `ensureVerified(id)` antes (exige check aprovado se item tem regras) | json `ReviewItem` | `rulesNotVerified` (msg multilinha), `Status inválido: <s>`, kind inválido; ordem: regras aplicadas ANTES do ensureVerified e do restante (write parcial possível) |

### 4.4 Regras (núcleo da política)
| `rules_for` (416,RO) | `findItem`, `applicableTopics(files,explicit)`; `TopicChecklist.compact/compactJSON` (ou json pretty de `TopicChecklist` se `verbose`) | sem regras: texto `Nenhuma regra aplicável a esses arquivos. Mesmo assim, chame submit_rule_check com results=[] para registrar a tarefa.`; senão JSON **compacto** | review_item soma `rules` do item e `target.file` aos filtros; `include_manual` detalha manuais |
| `submit_rule_check` (425) | decode `results` -> `[RuleAnswer{ruleId,verdict pass|fail|na,note}]` (aceita array ou string JSON); `store.submitCheck(task,files,topics,reviewItem,answers,verifyManual,author:.ai)`; `check.agentSummary(verbose)` | texto/JSON resumo (passed, warnings, manuais pending...); **roda scripts das regras** | `results deve ser uma lista de {ruleId, verdict: pass|fail|na, note}.`; `incompleteCheck`, `ruleNotFound`, `ambiguousRule`; W `.vibedeck/checks/<...>.json` (checkFileName) |
| `run_rule_tests` (434,RO) | `store.runRuleTests(files,topics,reviewItem,onlyTopics: files.isEmpty && item==nil)` | vazio -> `Nenhuma regra aplicável tem script.`; senão json `[{topic,ruleId,text,severity,command,verdict,exitCode,output}]` | **[EXT]** executa `$SHELL -lc <command>` (fallback `ClaudeCode.defaultShell`) por regra, em paralelo (<= nº CPUs, com lock por build-tool), env `VIBEDECK_FILES`; exit 0 cumpre, 77 n/a, outro viola; timeout/pgrep para matar filhos (RuleTests.swift L164-226). Apesar de RO, grava logs |
| `set_rule_test` (441) | `setRuleTest(rule_id,mode,command,reason)` | texto `Regra <8 primeiros do UUID>: <testState.label>.` | `mode deve ser script ou manual.`; `invalidRuleTest`; W tópico em `.vibedeck/rules` (+ `tests`) |
| `list_rule_topics` (448,RO) | `listTopics` | json `[{slug,title,description,tags,paths,rules:n}]` | R |
| `get_rule_topic` (450,RO) | `resolveTopicSlug`, `loadTopic` | json `TopicChecklist` | `Tópico de regras não encontrado` |
| `add_rule_topic` (452) | `createTopic(title,description,tags,paths)` | json `TopicChecklist` | W `.vibedeck/rules/<slug>.json`; sem paths = global |
| `add_rule` (459) | `addRule(Rule(text,details,severity,author:.ai), toTopic)` | json `{topic,ruleId(UUID),text}` | cria tópico se não existe; W |
| `move_rule_to_group` [+] (283) | `moveRuleToGroup(rule,group)` | json | W |
| `rename_rule_group` [+] (284) | `renameRuleGroup(topic,from,to)` | texto `Grupo de regras movido.` | W |
| `item_groups` [+] (278) | `concept`∈ItemConcept; `action`: list->`listItemDirectories` json; create->`createItemDirectory(path)`; move/rename->`moveItemDirectory(from,to)` texto `Grupo movido.`; move_item->`moveGroupedItem(reference,to)`; delete->`deleteItemDirectory(path,confirmed)` texto `Grupo apagado.` | misto | `Conceito inválido.`, `Operação de grupo inválida.`, `groupConfirmationRequired`, `groupConflict`, `invalidGroupPath`; W diretórios sob `.vibedeck/<concept>` |

### 4.5 Ideias
| `list_ideas` (468,RO) | `listIdeas` filtro status | json `[{group,slug,title,status,tags,rules:n,promotedTopic}]` | R |
| `get_idea` (471,RO) | `ideaDetail(ref)` | json | `Ideia não encontrada` |
| `add_idea` (473) | `createIdea(title,body,tags,author:.ai,reference)` | json `Idea` + campo `slug` mesclado (SlugAnd) | W `.vibedeck/ideas/...` |
| `update_idea` (479) | `setIdeaDependencies` (se `dependencies`; valida antes) depois `updateIdea{title,body,status,tags}` | json Idea+slug | `invalidIdeaDependency`, `Status inválido: <s>` |
| `add_idea_rule` (488) | `addRule(rule, toIdea)` | json `{idea,ruleId,text}` | W (regra rascunho) |
| `promote_idea` (720) | `unmatchedIdeaPaths`, `promoteIdea` | texto `Ideia promovida para o tópico de regras: <t>` (+ `\nAviso: globs da ideia que não casam nenhum arquivo foram copiados: a, b`) | `ideaNotImplementable`; W cria tópico + marca idea |
| `unpromote_idea` (722) | `loadIdea/resolveIdeaSlug`, `unpromoteIdea` | `A ideia não estava promovida.` / `Ideia despromovida; tópico removido: <t>` / `Ideia despromovida (o tópico já não existia).` | W |

### 4.6 Stack e padrões
| `list_stack` (347,RO) | `loadProject().stack`; badge via `StackService.badge()` só se stack não vazia (erro engolido -> null) | json `{stack:[StackItem], badge:<url|null>}` | **[EXT] rede** (badge) |
| `search_stack_icons` (349,RO) | `SkillIcons().search(query,category,limit)` + marca `inStack` | json `[{id,name,category,themed,aliases?,inStack}]` | **[EXT] rede**: `https://skill-icons.alanreisanjo.workers.dev/mcp` (Stack.swift L160, é outro servidor MCP via HTTP); `skillIconsUnavailable` |
| `add_stack` (356) | `StackService.add(icons,note,author:.ai)` | json de mudança | **[EXT] rede**; `unknownStackIcons` (lista sugestões); W `vibedeck.json` + atualiza badge no README? (ver StackService) |
| `remove_stack` (361) | `StackService.remove` | json | rede; `stackItemNotFound` |
| `update_stack` (363) | `setNote` (se `note` presente, mesmo vazio) e/ou `move(position)` | json `Change` | `Informe note ou position.`; rede |
| `list_patterns` (371,RO) | `PatternListing(store)` | json `{patterns:[{id,name,category?,summary?,note?,topic?,paths,rules:[Rule],author}]}` | R |
| `pattern_catalog` (373,RO) | `PatternCatalog.search(query)` (catálogo embutido) | json `[{id,name,category,summary,aliases?,rules:[texto],inProject}]` | R |
| `add_pattern` (375) | com `name`: `addCustomPattern(name,summary,rules,note,paths,author:.ai)` (exige rules); senão `addPatterns(refs,note,paths,author:.ai)` | json `PatternListing` | `Padrão personalizado precisa de rules.`, `Informe patterns (catálogo) ou name + rules.`, `unknownPatterns`; W vibedeck.json + cria tópico de regras por padrão |
| `remove_pattern` (384) | `removePatterns` | json PatternListing | `Parâmetro obrigatório: patterns`; remove tópicos |
| `update_pattern` (386) | `setPatternNote`/`setPatternPaths`/`movePattern` | json PatternListing | `Informe note, paths ou position.`, `patternNotFound` |

### 4.7 Agentes / comandos / skills (padrão repetido)
Resultado de get/add/update/next_step = json do registro com campo `slug` mesclado (SlugAnd: campos do registro + `slug`). list_* = linhas reduzidas. Arquivos: `.vibedeck/agents|commands|skills/<slug>.json`.
| `list_agents` (496) | `listAgents` | `[{slug,title,model,tags,nextSteps}]` | R |
| `get_agent` (498) | `resolveAgentSlug`, `loadAgent` | json+slug | `Agente não encontrado` |
| `add_agent` (500) | `createAgent(title,summary,model,tools,prompt,tags,author:.ai)`; se `provider_settings`: `updateAgent{providerSettings}` e recarrega | json+slug | W |
| `update_agent` (509) | `updateAgent(ref){campos presentes}` | json+slug | W |
| `add_agent_next_step` (519) | `addNextStep(to,kind(default agent),target,note)` | json+slug | `Tipo inválido: <k>`, `invalidNextStep` |
| `agent_flow` (526,RO) | `AgentFlow.json(from:...)` | json do grafo (ou `""` se nil) | R |
| `import_agents` (528) | `importAgents(provider,overwrite,author:.ai)` | claude: json `[slugs]`; codex: json `{slugs,warnings}` | lê `.claude/agents` (ver Core) ou `.codex/agents` de root e home; W |
| `list_commands` (531) | `listCommands` | `[{slug,title,argumentHint,model,tags,nextSteps}]` | R |
| `get_command` (533) | `resolveCommandSlug`,`loadCommand` | json+slug | |
| `add_command` (535) | `createCommand(...argumentHint...)` + providerSettings | json+slug | |
| `update_command` (545) | `updateCommand` | json+slug | |
| `add_command_next_step` (556) | `addCommandNextStep` | json+slug | |
| `command_flow` (563,RO) | `AgentFlow.json(kind:.command,...)` | json/`""` | |
| `import_commands` (565) | `importCommands` (`.claude/commands` ou `.codex/prompts`) | idem import_agents | |
| `list_skills` (568) | `listSkills` | `[{group,slug,title,summary,model,tags,nextSteps}]` | |
| `get_skill` (570) | `resolveSkillSlug`,`loadSkill` | json+slug | |
| `add_skill` (572) | `createSkill(...,reference)` + providerSettings | json+slug | cria SKILL.md-compatível |
| `update_skill` (581) | `updateSkill` | json+slug | |
| `add_skill_next_step` (591) | `addSkillNextStep` | json+slug | |
| `skill_flow` (598,RO) | `AgentFlow.json(kind:.skill)` | json/`""` | |
| `import_skills` (600) | `importSkills` (**async, @MainActor**) | idem | codex: **[EXT]** `CodexRPC` (spawna `codex app-server`, RPC `skills/list`); claude: só disco |

### 4.8 Workflows e execuções (runs)
Workflow: `.vibedeck/workflows/<slug>.json`; runs: `.vibedeck/runs/<workflow>/<run>/...`. Edição devolve json Workflow+slug.
| `list_workflows` (603) | `listWorkflows` | `[{slug,title,summary,input,tags,steps:[ids]}]` | |
| `get_workflow` (605) | `loadWorkflow` | json+slug | |
| `add_workflow` (607) | `createWorkflow(title,summary,input,maxSteps(>0 senão nil),tags,author:.ai)` | json+slug | |
| `update_workflow` (615) | `updateWorkflow{...; max_steps<=0 -> nil}` | json+slug | |
| `add_workflow_step` (624) | `addWorkflowStep(to,kind(default agent),target,note)`; se `max_visits`: `setWorkflowStepMaxVisits` | json `{slug,step:<id>,workflow}` | `Tipo inválido`, `invalidWorkflow` |
| `set_workflow_step_max_visits` (632) | `setWorkflowStepMaxVisits` | json+slug | `Parâmetro obrigatório: max_visits` |
| `remove_workflow_step` (638) | `removeWorkflowStep` | json+slug | remove transições para ela |
| `move_workflow_step` (643) | `moveWorkflowStep(to: position)` | json+slug | `Parâmetro obrigatório: position` |
| `add_workflow_transition` (649) | `addWorkflowTransition(from,to,when,verdict)` | json+slug | |
| `remove_workflow_transition` (657) | `removeWorkflowTransition(from,index)` | json+slug | `Parâmetro obrigatório: index` |
| `workflow_flow` (663,RO) | `workflowPlan(ref,input).json()` | json do plano | |
| `workflow_run_start` (668) | `startRun(workflow,input,from,provider)` + `WorkflowOrchestration.orchestratorPrompt` | json `{ref,action:<WorkflowRunAction>,prompt}` | provider só validado se informado (`Provedor inválido`); W cria run. **Não spawna processos**: o MCP só devolve prompt; orquestração via subagentes do cliente |
| `workflow_run_next` (674,RO) | `nextRunAction(run)` | json action | `runNotFound` |
| `workflow_run_step` (677,RO) | `runStepPrompt(run)` | **texto** (prompt da etapa) | |
| `workflow_run_record` (680) | `recordRun(run,verdict,summary,to,noneHolds)` | json action | W histórico do run |
| `workflow_run_ask` (688) | decode `questions` -> `[WorkflowQuestionDraft{question,context,options[{label,description}],multiple}]` (array ou string JSON); `askRun` | texto `Pergunta(s) gravada(s): 1, 2. Termine a etapa com a última linha: PERGUNTA` | `questions deve ser uma lista de {question, context, options: [{label, description}], multiple}.` |
| `workflow_run_questions` (690,RO) | `loadRun(resolveRunRef)`; `open=true` -> `openQuestions` | json array | |
| `workflow_run_answer` (695) | `answerRun(run,number,answer)` | json action | `Parâmetro obrigatório: number` |
| `workflow_run_list` (701,RO) | `listRuns(workflow)` filtro status | json `[{ref,workflow,input,status,current,steps:n,openQuestions:n,updatedAt}]` | |
| `workflow_run_show` (706,RO) | `loadRun` | json run completo | |
| `workflow_run_stop` (709) | `stopRun(run,reason)` | json | W |

### 4.9 IA / guia / catálogo / uso / reorganização
| `ai_guide` (394,RO) | `AgentsGuide.section(n)` / `.index` | **texto markdown** (embutido no binário: AgentsGuide.swift — portar o conteúdo) | seção inexistente: `Seção inexistente.` (usa `intValue` estrito) |
| `ai_catalog` (396,RO) | `kind=="kits"` -> `KitCatalog.kits` drop/prefix (limit 1..100 default 20); senão `store.aiCatalog(kind,offset,limit)` | json | kinds: agents, commands, skills, workflows, rules, kits |
| `ai_context` (398,RO) | `AIContextStore(root).page(id,offset,limit default 4000)` | json página com `nextOffset` | lê de `Application Support/VibeDeck/ai/<sha256(root real)>/` |
| `ai_usage` (412) | `AIUsageStore(root).list()` / `clear()` | json `[AIUsageRecord]` (mais recente primeiro) ou texto `Métricas locais apagadas.` | W apaga `.../ai/<hash>/usage/*.json` |
| `codex_usage` (264,RO) | `CodexQueries.limits(root)` | json `JSONValue` cru da resposta `account/rateLimits/read` | **[EXT]** spawna `codex app-server` (CodexRPC, JSON-RPC/stdio) |
| `claude_usage` (265,RO) | `ClaudeCode.loadUsage()` lê `~/Library/Application Support/VibeDeck/claude-usage.json` (Linux: `applicationSupportDirectory`) | json `ClaudeUsage` ou texto `Nenhum uso registrado. O usuário precisa ligar a statusline com `vibedeck usage install`.` | R (arquivo escrito pela statusline do Claude Code) |
| `reorganize_prompt` [+] (400,RO) | `ReorganizeDiscover.prompt/schema`, `reorganizeFingerprint` | json `{prompt,schema,fingerprint}` | R |
| `reorganize_analyze` [+] (402,RO) | `ReorganizeDiscover.analyze(store,provider,settings{model,effort})` | json Proposal | **[EXT] claude/codex**: `provider` obrigatório (`_ = req`); codex -> `CodexReadOnly` (app-server); claude -> `AIReadOnlyProcess.run` (executável via `RemoteExecution.executable`, pode ser **SSH** remoto); lock `ReorganizeLease`; `discoverFailed/TimedOut/InvalidAnswer`; `AIIntegrationError.unavailable` |
| `reorganize_validate` [+] (404,RO) | `ReorganizeDiscover.parse(answer, fingerprint)` | json | puro |
| `reorganize_apply` [+] (406) | `decodeProposal/decodeAcceptance` (strings JSON), `applyReorganization` | json relatório | W (move/renomeia/edita registros); exige aceite |
| `item_ai_prompt` [+] (408,RO) | `itemAIPrompt(kind,request,item)` | json `{prompt,schema}` | `Tipo inválido: use agent, command, skill ou workflow.` |
| `item_ai_apply` [+] (410) | `itemAIApply(kind,json,item)` | texto `Gravado: <slug>` | W; valida schema |

### 4.10 Nuvem — **REMOVER (decisão do mestre)**
| `cloud_check` [DEL] (267,RO) | `CloudSession.check(root)` | json `CloudSync` | **[EXT] git** (compara branch padrão local/origin) |
| `start_cloud_session` [DEL] (269) | `CloudSession.launch(root,description,allowDirty,provider,environment)` | json `{sync,url,output}` | **[EXT] claude / codex / git**; `cloudNotSynced/cloudDirty/claudeNotInstalled/cloudSessionFailed` |
Ao remover: apagar `CloudStart`, erros `cloud*`/`claudeNotInstalled` (se sem outro uso) e atualizar fixture.

### 4.11 Lista de conferência das 85 tools do contrato (todas mapeadas acima)
Projeto/links/tags: get_project, add_link, set_tags · Docs: list_docs, read_doc, write_doc · Revisões: list_review_groups, list_review_items, add_review_item, update_review_item · Regras: rules_for, submit_rule_check, run_rule_tests, set_rule_test, list_rule_topics, get_rule_topic, add_rule_topic, add_rule · Ideias: list_ideas, get_idea, add_idea, update_idea, add_idea_rule, promote_idea, unpromote_idea · Stack/padrões: list_stack, search_stack_icons, add_stack, remove_stack, update_stack, list_patterns, pattern_catalog, add_pattern, remove_pattern, update_pattern · IA/uso: ai_guide, ai_catalog, ai_context, ai_usage, codex_usage, claude_usage · Agentes: list_agents, get_agent, add_agent, update_agent, add_agent_next_step, agent_flow, import_agents · Comandos: list_commands, get_command, add_command, update_command, add_command_next_step, command_flow, import_commands · Skills: list_skills, get_skill, add_skill, update_skill, add_skill_next_step, skill_flow, import_skills · Workflows: list_workflows, get_workflow, add_workflow, update_workflow, add_workflow_step, set_workflow_step_max_visits, remove_workflow_step, move_workflow_step, add_workflow_transition, remove_workflow_transition, workflow_flow · Runs: workflow_run_start, _next, _step, _record, _ask, _questions, _answer, _list, _show, _stop · Nuvem [DEL]: cloud_check, start_cloud_session. (Total = 85.)
Obs.: no contrato, `write_doc` não tem `reference/generated`, `add_idea` não tem `reference`, `add_skill` não tem `reference`, `rules_for` não tem `verbose`, `submit_rule_check` não tem `verbose`: parâmetros novos no código (aditivos). O contrato guarda só `type/enum/items` por propriedade e `required` (ordenado).

## 5. Recursos MCP (L1396-1471)
`resources/list` (sem paginação; reconstruído a cada chamada, erros de I/O propagam como erro JSON-RPC) retorna fixos: `vibedeck://project` (name `vibedeck.json`), `vibedeck://stack`, `vibedeck://patterns`, `vibedeck://logs`, `vibedeck://logs/crashes`; dinâmicos: `vibedeck://docs/<slug>` (text/markdown), `reviews/<slug>`, `rules/<slug>`, `ideas/<slug>`, `agents/<slug>`, `commands/<slug>`, `skills/<slug>`, `workflows/<slug>` (application/json; names "Revisão: ", "Regras: ", "Ideia: ", "Agente: ", "Comando: ", "Skill: ", "Workflow: " + título; description = contagens/summary/status/model). `resources/read`:
- `project` -> conteúdo CRU de `vibedeck.json`; `reviews|rules|ideas|agents|commands|skills|workflows/<slug>` -> arquivo JSON cru do disco (`groupURL/topicURL/ideaURL/agentURL/commandURL/skillURL/workflowURL`); `docs/<slug>` -> `readDoc`; `patterns` -> `json(PatternListing)` pretty; `stack` -> `json(stack)` pretty; `logs` -> compacto, últimas 24h, nível >= warning, projeto atual, limit 50; `logs/crashes` -> compacto, 14d, nível crash, limit 50, sem filtro de projeto.
- URI desconhecida: `MCPError.invalidParams("URI desconhecida: <uri>")` (erro JSON-RPC aqui, pois não há try/catch no handler de resources). Slug sem sanitização explícita nos `*URL(slug)` (só `validatedRecordURL` em alguns): validar path traversal no port.
- Prompts: nenhum.

## 6. Dependências externas (resumo)
- **claude**: `reorganize_analyze` (provider=claude, via `AIReadOnlyProcess`, possivelmente SSH), `start_cloud_session` [DEL], `mcp install/uninstall`.
- **codex**: `codex_usage`, `reorganize_analyze` (provider=codex), `import_skills` (provider=codex), `start_cloud_session` [DEL] (todos via `codex app-server` JSON-RPC).
- **ssh**: apenas indireto — `RemoteExecution.executable(provider, root)` em `reorganize_analyze` pode resolver para launcher remoto (RemoteExecution.swift/SSHConnection.swift); demais tools MCP não usam SSH.
- **shell**: `submit_rule_check` e `run_rule_tests` (`$SHELL -lc`), regras script.
- **git**: `cloud_check` [DEL].
- **rede HTTP**: stack (`list_stack` badge, `search_stack_icons`, `add_stack`, `remove_stack`, `update_stack`) -> skill-icons worker.
- Só disco: todas as demais.

## 7. Dúvidas / a verificar
1. Negociação de `protocolVersion` e lista suportada do swift-sdk 0.12.1 (sem fonte local).
2. `notifications/cancelled`: SDK cancela a Task do handler? Replicar (abortar tool em voo) ou ignorar.
3. Texto exato de `MCPError.localizedDescription` (invalidParams/methodNotFound) no SDK 0.12.1 (afeta mensagens `isError`).
4. Conteúdo/efeitos de `StackService` (atualiza README/badge?), `submitCheck` (formato do check em disco e `agentSummary`), `AgentsGuide` (texto embutido enorme) e `AgentFlow.json` — exigem inventário Core em outras fases; aqui só mapeei a chamada.
5. Decidir se as 14 tools extras (fora do contrato) entram no port e se a fixture será regenerada (`mcp-contract.py snapshot`) já sem as 2 de nuvem.
6. `resources/list` em tool-less erro (ex.: diretório ausente) vira erro JSON-RPC; manter?
