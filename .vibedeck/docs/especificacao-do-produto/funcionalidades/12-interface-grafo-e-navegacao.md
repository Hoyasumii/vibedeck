---
author: ai
---
# FUN-012 — Interface, navegação e grafo

# FUN-012 — Interface, navegação e grafo

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

O app atual é macOS/SwiftUI. Tem janela por projeto, seções de conceitos, listas filtráveis por texto/tags, abas, painel de detalhe e inspector. Edições persistem diretamente e ações suportam desfazer/refazer conforme a operação.
Há painel de IA e terminal interativo. Mudanças externas são refletidas por observação dos arquivos.
O grafo oferece navegação por comunidades e relações. Gerar/atualizar é ação explícita com IA; exportação local/offline é separada. Resultado anterior é preservado se geração/validação falhar.

## Fluxo de uso

1. Abrir projeto e localizar conceito por seção/busca.
2. Consultar ou editar item e inspecionar regras/contexto.
3. Abrir chat/terminal ou navegar no grafo conforme a tarefa.
4. Acompanhar progresso e cancelar operações que oferecem cancelamento.

## Regras e limites atuais a revisar

Não tratar grafo como fonte infalível ou aprovação de código. Abrir sua aba não deve iniciar geração automaticamente. Recursos de UI não são pré-requisito do CLI/MCP.

## Direção desejada já registrada

Usuário indicou uma referência visual no documento 01 e quer caminho fácil e visível para entender o produto. A referência foi preservada; seu conteúdo não pôde ser inspecionado nesta coleta.

## Decisões para o usuário

Definir o que mudar em sidebar, abas, inspector, terminal e grafo; decidir quais interfaces Windows/Linux serão entregues. SwiftUI hoje não comprova UI multiplataforma.

## Cenário de aceite proposto

AC-012: mudança externa atualiza a exibição sem sobrescrever edição humana; cancelar geração preserva grafo anterior; operação básica MCP funciona sem janela do app.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckApp/ProjectWindow.swift](../../../../Sources/VibeDeckApp/ProjectWindow.swift)
- [Sources/VibeDeckApp/ProjectModel.swift](../../../../Sources/VibeDeckApp/ProjectModel.swift)
- [Sources/VibeDeckCore/GraphHTML.swift](../../../../Sources/VibeDeckCore/GraphHTML.swift)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
