# Ajuste pós-revisão (AJUSTAR → implementar)

- Core: `ProjectStore.requireIdeaDependenciesMet(_:)` relê as dependências do disco e lança `ideaNotImplementable` (falha de leitura também bloqueia).
- App: `ProjectModel.promoteIdea(_:skippingPaths:forImplementation:)` — com `forImplementation`, consulta o Core antes de promover; `ideaDependenciesMet(_:)` mostra o erro.
- IdeaView: o clique em Implementar usa `ideaDependenciesMet` (sem `try?`); o diálogo "Globs que não casam" guarda `promotionForImplementation` e, ao confirmar ("sem eles"/"com eles"), promove com `forImplementation: true` → dependência reaberta com o diálogo aberto não promove nem envia à IA.
- Testes: `dependencyReopenedWhileGlobsDialogIsOpenBlocksPromotion` (app) e asserts de `requireIdeaDependenciesMet` em RulesTests.
- swift test: 329 Core + 71 app passaram. Check ed9811e2 aprovado (207 scripts; 48 manuais não verificadas).
