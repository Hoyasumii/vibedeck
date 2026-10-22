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
