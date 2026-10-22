# PEDIDOS-CORE (app -> Core Rust) — consolidado pelo líder APP

O app só fala MCP (A3). O que o Core não expõe vira `CoreError.unsupported` no app (a ação falha com mensagem clara) até a tool existir.
Fonte de verdade do que existe: tools.md (binário real). Formato abaixo: tool, argumentos, retorno, de onde o app chama.

## P1 — Escrita genérica de registros (essencial: sem isto o app é só leitura)
O app edita registros inteiros (campo a campo, undo/redo guarda o valor anterior) e hoje grava o arquivo inteiro.
- `put_record(kind: reviews|rules|ideas|agents|commands|skills|workflows, slug: string, record: string)`
  `record` = JSON exato do arquivo (mesmo formato canônico que o Core emite; o Core valida contra o schema do modelo, grava atômico,
  cria subpastas do slug `grupo/sub/slug`, preserva author/ids/datas vindos do registro, NÃO força author=ai). Retorna `Salvo: <slug>`.
  Chamado por: `CoreStore.saveRecord` (ProjectModel.mutate*, create*, undo/redo).
- `delete_record(kind, slug)` — remove o arquivo (idealmente para a lixeira do sistema / `.vibedeck/.trash` para desfazer). Retorna `Removido: <slug>`.
  Para `rules`: o Core deve despromover ideias do tópico e soltar padrões que ele impunha (hoje `releaseOrphanedIdeas/Patterns`).
- `put_project(project: string)` — grava `vibedeck.json` inteiro (stack, patterns, links, claude, reviewKinds). Hoje o app reordena stack/padrões e edita links localmente.

## P2 — Leituras que faltam
- `list_checks()` -> JSON `[RuleCheck]` (histórico de `.vibedeck/checks`, mais recente primeiro). Hoje a lista de checks do app fica vazia.
- `list_docs`: incluir `modified` (ISO-8601) em cada linha (a lista de Docs mostra "há 2 dias").
- `get_run`/`workflow_run_show` já existe; falta `workflow_run_delete(run)` (apagar execução e artefatos) e `workflow_run_checkpoint(run, step, output, completed)` + `workflow_run_save_output(run, output)` (o chat grava a saída parcial de uma etapa interrompida).
- `delete_doc(slug)` (o CLI só tem `docs unlink`; precisa apagar/lixeira o doc comum e, para vinculado, remover o vínculo).

## P3 — Eventos e consistência
- Notificações de mudança: o app precisa saber de alterações externas (CLI/IA/Finder). Pedido: `notifications/resources/list_changed` + `notifications/resources/updated` com `uri`, emitido pelo servidor ao observar `.vibedeck/` e `vibedeck.json` (capability `resources.listChanged=true`, `subscribe=true`); alternativa barata: tool `project_revision()` -> `{revision: string}` (hash de mtimes) para o app consultar a cada 2 s em projetos SSH.
  Sem isso: local usa FSEvents no app; SSH faz polling completo a cada 5 s.
- Anexos: `import_attachment(owner: string, name: string, data_base64: string)` -> link markdown `../attachments/...` (arrastar/colar imagem em doc/ideia). Para SSH o arquivo precisa subir pelo Core.

## P4 — Regras e execução (a UI de execução de regras mostra progresso por script)
- `run_rule_tests`/`submit_rule_check` são chamadas únicas (sem progresso por regra). Pedido: aceitar `progress_token` e emitir `notifications/progress` com `{ruleId, state: running|pass|fail|na, output}` por script; e `cancel` por `notifications/cancelled`.
- `rule_verification_status(review_item)` -> `{problems:[string], required_topics:[slug]}` (hoje o app usa `verificationProblems(for:)` e `requiredTopics(for:)` para o selo "regras verificadas" de cada item de revisão).
- `update_rule(topic, rule_id, text, details, severity)`, `remove_rule(topic, rule_id)`, `move_rule(...)`: o app edita regras no tópico inteiro; com P1 funciona via `put_record(rules)`, mas o teste da regra (`tests/<topic>/<rule>.sh`) fica órfão ao editar/remover.

## P5 — IA descobrir/gerar (prompts, schemas e validação ficam no Core)
O app hoje carrega os prompts/schemas dos fluxos "Descubra" e valida as respostas. Já existem `reorganize_*` e `item_ai_*`. Faltam pares prompt/validate/apply para:
- `rule_discover_*` (escopo, entrevista, detalhes, veredito) -> hoje `RuleDiscover` (Swift) migrado para o app.
- `review_discover_*` (propor itens de revisão) -> hoje `ReviewDiscover` migrado para o app.
- `doc_generate_prompt/validate/apply` -> hoje `DocGenerate` migrado para o app.
Enquanto não existirem, esse código Swift (prompts, schemas, parse) permanece no app (lista em app-only.md) e só a gravação passa por tools/put_record.

## P6 — Outros
- `workflow_run_start` com `provider` e retomada por `idea`: o app usa `implementIdeaRun(idea, workflow, restart, provider)` e `ideaRun(idea, workflow)` (execução ligada a uma ideia) — pedir `idea_implement(idea, workflow?, restart?, provider?)` -> `{topic, run_ref, prompt}` e `idea_run(idea, workflow)`.
- `stack_sync_readme` (badge do README) — hoje `StackService.syncReadme()`; `add_stack/update_stack` já atualizam? Confirmar.
- `claude_install_statusline/stop_hook` (`vibedeck usage install`, `vibedeck hook install`) como tools ou chamada CLI documentada (o app chama o CLI do bundle).
- `ai_usage` registra uso: o app grava `AIUsageRecord` de cada turno; pedir `ai_usage_record(record)`.

## P7 — Descobertos durante a migração (todos viram `CoreError.unsupported` ou degradam no app)
- `put_project` deve atualizar o bloco de badge da stack no README.md (o app antes chamava `StackService.syncReadme()` após cada mudança de stack).
- `add_pattern`/`add_stack`/`add_*`: parâmetro `author` (`human`|`ai`); o app cria registros como `human`, as tools MCP gravam `ai`.
- `item_groups` `move_item` com destino raiz: hoje `to` vazio conta como ausente (erro). Aceitar `to: "/"` ou `root: true`.
- `item_groups` `delete`/`move`: devolver o recibo para desfazer (hoje o app só desfaz mover; apagar grupo não tem desfazer).
- `workflow_run_resume(run)`: uma execução parada volta a andar (hoje `resumeRun` do Swift). `workflow_run_start` com mesma entrada já reinicia.
- `reorganize_restore(receipt, forward)`: desfazer/refazer reorganização (o app aplica via `reorganize_apply` e perde o desfazer sem isto).
- `import_attachment` (P3), `delete_doc`, `list_checks`, `put_record`, `delete_record`, `put_project` (P1/P2) — sem eles o app é somente leitura.
- `graph_generate` para projetos SSH (o grafo semântico hoje roda no Mac, só local).
- Receipt de `reorganize_apply`: o app decodifica `before/after` como `Data` Swift (base64). Confirmar a codificação dos bytes no JSON do Rust (`ser_bytes_map`).

---
# STATUS (executor CORE) — `vibedeck mcp --app` / `vibedeck mcp serve --app`

Tools abaixo só existem com `--app` (catálogo padrão inalterado; contrato passa). Resultado em `content[0].text`; falha = `isError`.
`list_docs` do modo app substitui o padrão. Em modo app, tools de criação aceitam `author: "human"|"ai"` (padrão `ai`): add_review_item, add_rule, add_idea, add_idea_rule, add_stack, add_pattern, add_kit, add_agent, add_command, add_skill, add_workflow.

## Tools (nome(args) -> retorno)
- `put_record(kind: reviews|rules|ideas|agents|commands|skills|workflows, slug, record: string JSON|objeto)` -> `Salvo: <slug>`. Valida modelo, atômico, subpastas, preserva author/ids/datas.
- `delete_record(kind, slug)` -> `Removido: <slug>`. Cópia em `.vibedeck/.trash/<carimbo>/<dir>/<slug>.json` (desfazer = put_record com esse conteúdo). rules solta ideias/padrões órfãos. Scripts em `.vibedeck/tests/` NÃO são tocados (ficam, para o desfazer funcionar).
- `put_project(project: string JSON)` -> `Salvo: vibedeck.json` (+ `\nAviso: ...` se o badge do README não atualizou; só sincroniza se a stack mudou; usa rede do Skill Icons).
- `list_checks()` -> `[RuleCheck]` mais recente primeiro.
- `list_docs()` -> `[{group,slug,title,tags,modified(ISO-8601 Z),linked?,target?,broken?}]`.
- `delete_doc(slug)` -> `Removido: <slug>` (lixeira; vinculado: só o vínculo).
- `workflow_run_delete(run)` -> `Removido: <ref>`.
- `workflow_run_checkpoint(run, step, output?, completed?, verdict?)` -> `Salvo: <ref>`.
- `workflow_run_save_output(run, output)` -> texto de referência (caminho em `outputs/`).
- `workflow_run_resume(run)` -> `{ref, run}`.
- `workflow_run_restart(run)` -> `{ref, run}`: reinício do começo (novo ciclo, mantém histórico, fecha perguntas); funciona em execução parada/em andamento/terminada. (Bug: `workflow_run_start` com mesma entrada não reinicia execução em andamento — `engine::restart` sai cedo; o Swift só tinha `restartFromBeginning` no app, sem equivalente de CLI, então não há `runs start --restart`.)
- `import_attachment(owner, name, data_base64)` -> link markdown (`![n](../attachments/…)`; `../` por componente de `owner`).
- `rule_verification_status(review_item)` -> `{problems:[string], required_topics:[slug]}`.
- `project_revision()` -> `{revision}` (sha256 de caminho+tamanho+mtime de vibedeck.json e `.vibedeck/` exceto `.trash`).
- `reorganize_restore(receipt: string JSON, forward: bool)` -> `Desfeito.`/`Refeito.`.
- `idea_implement(idea, workflow?, restart?, provider?, skipping_paths?)` -> `{topic, run_ref|null, prompt, run|null}` (exige ideia elegível + dependências; promove; com workflow retoma/reinicia/cria a execução da ideia).
- `idea_run(idea, workflow)` -> `{ref, run}` ou `null`.
- `ai_usage_record(record: string JSON UsageRecord)` -> `Salvo: <id>` (aparece em `ai_usage`).
- `release_orphaned()` -> `{ideas:[slug], patterns:[...]}` soltos. O Swift chamava ao abrir o projeto e após mudança externa em tópicos: o app deve chamar nesses dois momentos.
- `item_groups` `move_item` aceita `to: "/"` como raiz (também fora do modo app).

## Notificações (modo app)
- initialize: `resources: {subscribe: true, listChanged: true}`. Polling de mtimes a cada ~1 s; ao mudar `.vibedeck/` ou `vibedeck.json` emite `notifications/resources/list_changed` e, para cada URI assinada por `resources/subscribe`, `notifications/resources/updated {uri}`. Escritas do próprio app também disparam.
- Progresso: `tools/call` com `_meta.progressToken` em `run_rule_tests`/`submit_rule_check` emite `notifications/progress` com `progress` crescente, `message` = JSON compacto `{ruleId,state,output,topic}` e os mesmos campos no nível de `params` (`state`: running|pass|fail|na).
- Cancelamento: `notifications/cancelled {requestId}` interrompe os scripts (a thread de leitura trata na hora, mesmo durante a execução); a chamada responde `isError` "Execução cancelada." e `submit_rule_check` não grava check. Cancelamento que chega antes da chamada começar também vale. Demais requisições seguem sequenciais.

## Recibo de reorganize_apply
`before`/`after`: `{caminho: base64 padrão com "=">}` (mesmo `Data` do JSONEncoder Swift), mais `createdDirectories` e `pathMoves`. `reorganize_restore` aceita exatamente esse JSON.

## Pedidos P1–P7
- P1 put_record/delete_record/put_project: FEITO.
- P2 list_checks, modified, workflow_run_delete/checkpoint/save_output, delete_doc: FEITO.
- P3 eventos (list_changed/updated + project_revision) e import_attachment: FEITO.
- P4 progresso, cancelamento, rule_verification_status: FEITO. update_rule/remove_rule/move_rule dedicados: NÃO FEITO (cobertos por put_record(rules); script órfão fica por design).
- P5 descobrir/gerar por IA: fora (fica no app).
- P6 idea_implement/idea_run, ai_usage_record, author: FEITO. stack_sync_readme: já ocorre em add_stack/remove_stack/update_stack e em put_project. claude_install_statusline/stop_hook como tool: NÃO FEITO (app chama o CLI `vibedeck usage install` / `vibedeck hook install` do bundle).
- P7 put_project+badge, author, `to:"/"`, workflow_run_resume, reorganize_restore, receipt base64: FEITO. Recibo de desfazer para `item_groups` delete/move: NÃO FEITO (não pedido nesta rodada). graph_generate via SSH: NÃO FEITO.
