# Revisão — Dependências entre ideias

Veredito: AJUSTAR

## Evidências
- `swift test`: 329 + 70 testes passaram (exit 0).
- Check 1e4228b7 aprovado (236 regras por script). 51 manuais pendentes, entre elas as 22 do tópico `dependencia-de-ideias`.
- Core coeso: `IdeaImplementation.dependencyBlockers/dependents/dependencyProblem` são funções puras.
  `ProjectStore.setIdeaDependencies` valida antes de gravar. `implementableIdea` é o portão único,
  usado em `WorkflowRuns.implementIdeaRun`, `ProjectModel.currentImplementationIdea` e `ClaudeSession` (botão e chat).
- CLI `ideas depend|undepend` e MCP `update_idea.dependencies` passam pelo mesmo `setIdeaDependencies`.
  `ideas show --json` e `get_idea` usam o mesmo `IdeaDetail`. O desvio de `add/remove_idea_dependency` foi justificado pelo orçamento MCP.

## Ajuste obrigatório
1. **`IdeaView.swift:303-316` + `:394-401`**, caminho Implementar de uma ideia ainda não aprovada (promover e implementar):
   - As dependências são conferidas uma única vez, ao clicar.
   - Se os globs não casam arquivos, `readyToPromote` abre o diálogo e devolve `false`. Ao confirmar
     "Promover sem/com eles", o app chama `model.promoteIdea` e depois `implement(topic)`, que chama `session.ask(prompt)`.
     Nenhum dos dois relê as dependências do disco.
   - Uma dependência reaberta enquanto o diálogo está aberto leva à promoção das regras e ao envio do pedido ao provedor.
     Isso fere os critérios 6 e 7 (regras F14AF789 e 6E15FBA4).
   - Além disso, `implement(_:)` envia o prompt sem passar por portão nenhum do Core.

   Correção sugerida: ao confirmar o diálogo, quando `then` for a implementação, chamar de novo a checagem de
   dependências do Core antes de `promoteIdea`. Por exemplo, extrair um helper `dependencyBlockersMessage()` usado em
   `onImplement` e nos botões do diálogo, ou fazer `implement` reconferir antes de promover. Adicionar um teste
   no app ou no Core que cubra esse caminho.

## Observações menores (não bloqueiam)
- `IdeaView.swift:308` usa `try?`. Se `ideaDetail` falhar, a checagem é ignorada e o fluxo segue
  (fail-open antes da promoção). Prefira tratar o erro como bloqueio.
- No MCP, `update_idea` grava as dependências antes dos outros campos. Se o `updateIdea` seguinte falhar,
  a gravação fica parcial. O risco é baixo.
- A folga do orçamento MCP é de 9 caracteres. Vale registrar isso como item de revisão ou ideia.

## Revisão 2 (após ajuste) — APROVADO
- Ajuste obrigatório resolvido: `ProjectStore.requireIdeaDependenciesMet` (Core, relê do disco; falha de leitura bloqueia); `ProjectModel.promoteIdea(..., forImplementation:)` consulta o Core antes de promover; `IdeaView` guarda `promotionForImplementation` e os dois botões do diálogo de globs promovem com a checagem; Cancelar limpa o estado. `try?` do clique removido.
- Teste `dependencyReopenedWhileGlobsDialogIsOpenBlocksPromotion` cobre o caminho (nada muda no disco; promove após concluir a dependência).
- swift test: 329 Core + 71 app passaram. Check e4cf8d0a aprovado (207 scripts; 48 manuais não verificadas).
- Pendências menores aceitas (não bloqueiam): `update_idea` no MCP não é atômico; catálogo MCP a 9 caracteres do limite.
