# Plano — Dependências entre ideias

Ideia: `dependencia-de-ideias` (A9B694ED…), status approved, readiness viável. Tópico promovido: `dependencia-de-ideias`
(22 regras manuais `must`). Especificação = corpo da ideia (critérios 1–15); este plano não a substitui.

## Usuários, entradas e saídas
- **Usuário do app**: edita Dependências (seleção múltipla, remoção individual, undo) e vê Dependentes em `IdeaView`;
  Implementar (botão / chat / sheet) mostra os impedimentos em pt-BR.
- **Agentes via CLI/MCP**: adicionam/removem vínculos; `ideas show --json` e `get_idea` retornam
  `dependencies`, `dependents` e `dependencyBlockers` equivalentes.
- **Entrada persistida**: `dependencies: [UUID]` no JSON da ideia (omitido quando vazio). Dependentes são derivados.

## Evidências da arquitetura (lidas)
- `Rules.swift:244` `Idea` com decode tolerante / encode omitindo vazios; `IdeaImplementation.isEligible` (pura, só
  estado próprio); `implementBlocker`; `contentFingerprint` exclui status/tags/promoção.
- `ProjectStore.swift:1140-1270` CRUD de ideias (sem estado, `loadIdea`/`saveIdea` via `VDJSON` + `AtomicFile`).
- `WorkflowRuns.swift:569` `implementIdeaRun` checa só `isEligible`.
- `ProjectModel.swift:941` `currentImplementationIdea` (relê do disco; usado por `WorkflowView.IdeaImplementationSheet`
  em selectWorkflow/confirm/finish) e `:989` `prepareIdeaImplementation` (promove → run → prompt).
- `ClaudeSession.swift:19/53` `requestIdeaImplementation` e intent do chat usam `isEligible`.
- `IdeaView.swift:211-221` caminho onImplement: ideia não `approved` sem blocker → **promove antes** de implementar
  (precisa checar dependências antes da promoção — critério 7).
- CLI `Ideas` (`CLI.swift:929`), MCP `get_idea`/`update_idea` (`MCPServer.swift:1073`); contrato MCP em
  `Tests/Fixtures/mcp-contract.json` + `mcp-budget-baseline.json` (scripts `scripts/mcp-contract.py`,
  `scripts/test-ai-efficiency.sh`).
- Schema `schema/v1/idea.schema.json`; worker copia via `npm run sync` (não editar `worker/public`).
- Revisões abertas: nenhuma nas áreas afetadas (3 abertas: ReviewGroupView, prioridade, stack/padrões). Padrões: nenhum.

## Módulos e responsabilidades
1. **Core / modelo (`Rules.swift`)**
   - `Idea.dependencies: [UUID]` (decode `?? []`, encode só se não vazio, dedupe na decodificação preservando ordem).
   - Fora do `contentFingerprint` (decisão: vínculo é metadado de ordem, como status/tags; não invalida a avaliação).
   - `IdeaDependencyBlocker: Codable` `{ id, slug?, title?, status? }` + `message` pt-BR:
     `Depende de "<título>" (<status.label>).` / `Depende de uma ideia ausente: <UUID>.`
   - `IdeaImplementation.dependencyBlockers(of:in:)` pura (lista completa; só `.done` satisfaz).
2. **Core / store (`ProjectStore.swift`)** — validação centralizada, lendo do disco a cada operação:
   - `setIdeaDependencies(_ ref, _ ids:)`, `addIdeaDependencies(_ ref, _ refs:)`, `removeIdeaDependencies(_ ref, _ refs:)`:
     resolvem refs (slug/UUID/prefixo/título), rejeitam autorreferência, inexistente e ciclo (DFS no grafo atual com
     a nova aresta) **antes** de gravar; nova `VibeDeckError` (ex. `invalidIdeaDependency(String)`) em pt-BR.
   - `ideaDependents(_ id) -> [(slug, Idea)]` (derivado; ninguém grava lista inversa).
   - `ideaDependencyBlockers(_ ref)`.
   - `implementableIdea(_ ref) throws -> (slug, Idea)`: relê, exige `isEligible` e zero blockers; erro lista todos.
3. **Workflow (`WorkflowRuns.swift`)**: `implementIdeaRun` usa `implementableIdea` (iniciar, retomar e reiniciar).
4. **App**
   - `ProjectModel`: `currentImplementationIdea` delega a `store.implementableIdea` (cobre sheet e
     `prepareIdeaImplementation` padrão/workflow antes de promover/criar run/enviar prompt);
     `setIdeaDependencies(slug, ids, undo:)` via Core com undo (undo revalida; erro → `errorMessage`);
     `ideaDependents(id)` derivado de `ideas` (atualiza ao vivo pelo watcher).
   - `IdeaView`: segunda linha do header (sem alterar largura mínima) com **Dependências** (chips com ✕ +
     menu/popover de seleção múltipla sobre todas as ideias do projeto, incl. `done`, exceto a própria) e
     **Dependentes** (links); botão Implementar desabilitado/`help` com impedimentos; `onImplement` checa
     dependências no Core antes de qualquer promoção.
   - `ClaudeSession`: `requestIdeaImplementation` e intent do chat (modos ask/standard/workflow) chamam
     `implementableIdea`; bloqueado → `fail(<motivos>)`, sem `ideaRequest`, sem envio ao provedor.
   - Logs: ações sem conteúdo da ideia (slug/contagem apenas).
5. **CLI**: `ideas depend <idea> <deps…>` e `ideas undepend <idea> <deps…>`; `ideas show` (texto + `--json`
   com campos extras `dependents`, `dependencyBlockers`, mantendo os campos da ideia).
6. **MCP**: `add_idea_dependency` / `remove_idea_dependency` (`idea`, `dependencies: [string]`);
   `get_idea` ampliado com os mesmos campos do CLI (struct de detalhe compartilhada no Core para equivalência).
   Atualizar fixtures de contrato/orçamento MCP pelos scripts existentes.
7. **Schema**: `dependencies` opcional `array` de `string` `format: uuid` + `pattern` UUID, `uniqueItems: true`;
   `npm run sync` + `npm run typecheck` no worker.
8. **Docs**: README, `.vibedeck/guide.md` (via `AgentsGuide.swift`, seção Ideias + comandos úteis).

## Testes (critérios 1–13)
- `RulesTests`: decode legado → `[]`; encode omite vazio; roundtrip com vários UUIDs únicos; blockers por status
  (new/exploring/approved/discarded bloqueiam, done satisfaz); combinação approved+discarded+ausente (UUID) em pt-BR.
- `ProjectStoreTests`/`WorkflowRunsTests`: autorreferência, inexistente, A→B/B→A, A→B→C/C→A sem gravação
  (bytes iguais); dependentes diretos (A,C→B; D→A não aparece em B; sem campo inverso); remoção 1 de 3;
  aprovada com 2 deps e 1 done bloqueia; arquivo de dependência removido bloqueia; `implementIdeaRun`
  bloqueado sem criar/alterar run (start/resume/restart) e reaberta externamente bloqueia; concluir última
  dependência libera sem criar run.
- `RuleDiscoverTests`: avaliação viável com dependência pendente segue `approved` sem promover.
- `IdeaEvaluationTests` (app): `prepareIdeaImplementation` padrão e workflow bloqueados → ideias, tópicos e runs
  iguais e prompt não emitido; `requestIdeaImplementation` não cria `ideaRequest`; undo de dependências.
- Schema: validar exemplos (sem campo, vários UUIDs, UUID inválido, duplicata) — sem `jsonschema`/ajv local;
  usar validador disponível (ex. `npx ajv-cli`) ou teste Swift do conteúdo do schema; registrar a limitação.

## Restrições
`ProjectStore` sem estado; `VDJSON` + `AtomicFile.write`; vazios omitidos; `VibeDeckError` pt-BR; undo no app;
sem execução automática; escolha de modo só no app (não no CLI/MCP); não ampliar para SSH; não trocar provedor.

## Critério de conclusão
`swift test` verde; schema validado; `npm run typecheck`; `graphify update .`; `rules_for` + `submit_rule_check`
com `passed=true` para os arquivos alterados. Critério 15: verificar com as ferramentas o check pendente de
`Tests/VibeDeckAppTests/IdeaEvaluationTests.swift` e o bloqueio relatado de `SSHProjectView.swift`, sem presumir aprovação.

## Decisões tomadas sem pergunta (derivadas da spec/padrões)
- Dependências fora do `contentFingerprint` (não exigem reavaliação pela IA).
- Nomes das operações CLI/MCP (`depend`/`undepend`, `add_/remove_idea_dependency`).
- Dependências de ideias `done`/`discarded` são editáveis normalmente; o bloqueio só vale na implementação.
