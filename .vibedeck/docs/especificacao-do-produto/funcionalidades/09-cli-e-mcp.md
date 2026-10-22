---
author: ai
---
# FUN-009 — CLI e MCP

# FUN-009 — CLI e MCP

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

O executável vibedeck expõe operações do Core para usuários e automação. --json fornece saídas estruturadas onde disponível; --ai identifica autoria nas operações correspondentes.
vibedeck mcp inicia servidor por stdio, com ferramentas e recursos do projeto. CLI/MCP compartilham Core Swift hoje. O transporte serializa mensagens para evitar intercalação em stdout.
Há configuração de clientes Claude/Codex; o caminho atual de compatibilidade Codex inclui adaptador Python conforme o instalador documentado. Isso é limitação atual a revisar na distribuição Rust, não requisito desejado para o futuro.

## Fluxo de uso

1. Disponibilizar executável e raiz do projeto.
2. Configurar cliente e iniciar processo MCP por stdio.
3. Negociar conexão, listar ferramentas e chamar operação.
4. Receber resposta estruturada; persistência usa o mesmo Core.

## Regras e limites atuais a revisar

Não presumir que todo botão do app tem ferramenta equivalente: Resolver e geração assistida possuem diferenças de canal. Manter inventário real de comandos, argumentos e schemas antes de alegar paridade completa.

## Direção desejada já registrada

Core/CLI/MCP Rust com artefatos pré-compilados e poucos pré-requisitos. Etapa 02 comprova conjunto mínimo; etapa 04 alcança substituição/paridade completa.

## Decisões para o usuário

Definir comandos/ferramentas prioritários, protocolo de erros, matriz de sistemas/CPUs, instalação/atualização e cliente para prova. Binário único ou múltiplos executáveis ainda é decisão arquitetural.

## Cenário de aceite proposto

AC-009: inicialização e chamada MCP real sem logs contaminando stdout; amostra lê/grava projeto temporário sem toolchains no destino. Ferramentas não migradas são declaradas na entrega parcial.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/vibedeck/CLI.swift](../../../../Sources/vibedeck/CLI.swift)
- [Sources/vibedeck/MCPServer.swift](../../../../Sources/vibedeck/MCPServer.swift)
- [Sources/vibedeck/SerializedStdioTransport.swift](../../../../Sources/vibedeck/SerializedStdioTransport.swift)
- [Sources/VibeDeckCore/CodexMCP.swift](../../../../Sources/VibeDeckCore/CodexMCP.swift)
- [Package.swift](../../../../Package.swift)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
