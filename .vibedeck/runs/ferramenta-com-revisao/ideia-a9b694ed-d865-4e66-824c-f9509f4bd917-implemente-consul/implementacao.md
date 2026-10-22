# Implementação — Dependências entre ideias

## Alterações
- Core `Rules.swift`: `Idea.dependencies: [UUID]` (decode tolerante com dedupe, omitido vazio, fora do fingerprint);
  `IdeaLink`, `IdeaDependencyBlocker` (mensagens pt-BR, UUID para ausente), `IdeaDetail`;
  `IdeaImplementation.dependencyBlockers/dependents/dependencyProblem` (self, inexistente, ciclo por DFS).
- Core `ProjectStore.swift`: `setIdeaDependencies` / `addIdeaDependencies` / `removeIdeaDependencies` (validam antes de gravar),
  `ideaDetail`, `implementableIdea` (portão único); erros `invalidIdeaDependency`, `ideaNotImplementable`.
- `WorkflowRuns.implementIdeaRun`: relê dependências em iniciar/retomar/reiniciar.
- App: `ProjectModel.currentImplementationIdea` usa o portão do Core (cobre sheet e `prepareIdeaImplementation`);
  `setIdeaDependencies` com undo + log sem conteúdo; `ideaDependents`/`ideaDependencyBlockers` derivados.
  `IdeaView`: linha Dependências (chips com ✕, popover de seleção múltipla incluindo done) e Dependentes (links);
  Implementar desabilitado com motivos; caminho de promoção checa dependências antes de promover.
  `ClaudeSession`: botão e intents do chat passam pelo portão do Core (falha sem ideaRequest nem envio).
- CLI: `ideas depend|undepend`; `ideas show` (texto e `--json` com `dependents`/`dependencyBlockers`).
- MCP: `get_idea` retorna `IdeaDetail`; `update_idea` aceita `dependencies` (lista completa).
  **Desvio do plano**: as tools `add/remove_idea_dependency` não cabiam no orçamento do catálogo MCP
  (limite 70% da baseline = 29703; com elas 30184). Com o parâmetro: 29694 (contrato ok).
- Schema `idea.schema.json`: `dependencies` array de UUID (pattern + format) com `uniqueItems`; `npm run sync`.
- Docs: README, AgentsGuide (→ `.vibedeck/guide.md` regenerado pelo CLI).

## Evidências
- `swift test`: 329 + 70 testes passando. Novos: RulesTests (persistência, integridade/ciclos com bytes iguais,
  estados, combinação approved+discarded+ausente, 1 de 2 done, dependentes diretos, remoção 1 de 3, schema),
  WorkflowRunsTests (start/resume/restart bloqueados, run intacta), RuleDiscoverTests (aprovação preservada),
  IdeaEvaluationTests (padrão/workflow/chat sem efeitos, reabertura externa, undo).
- Schema via ajv-cli (draft2020 + formats): sem campo/vários UUIDs válidos; UUID inválido e duplicata rejeitados.
- `npm run typecheck` ok (node do mise; `npm`/`npx` não estão no PATH padrão).
- CLI↔MCP: vínculo criado pelo CLI, removido pelo MCP; ambos rejeitam autorreferência e ciclo; detalhes equivalentes.
- `scripts/mcp-contract.py check` ok. `graphify update .` + `vibedeck graph export` (HTML offline).
- Checks: 8a3e9409 (arquivos alterados, passed) e c6a60cf9 (SSHProjectView.swift, passed; critério 15).
  Manuais: 53 pendentes (incluindo as 22 do tópico dependencia-de-ideias), não verificadas nesta etapa.
