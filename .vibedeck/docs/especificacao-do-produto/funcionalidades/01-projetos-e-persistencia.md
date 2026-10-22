---
author: ai
---
# FUN-001 — Projetos e persistência

# FUN-001 — Projetos e persistência

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Abrir uma pasta local, reconhecer vibedeck.json e, quando ausente, oferecer inicialização. Dados de produto ficam no repositório: manifesto, documentos Markdown e registros JSON em .vibedeck/. Projetos recentes facilitam a reabertura.
O Core Swift atual lê/grava arquivos; o app mantém um espelho em memória e acompanha mudanças externas. Escritas passam pelo helper atômico. IDs e autoria permitem distinguir itens humanos e de IA. Configurações de máquina e logs não se confundem com o conteúdo versionável do projeto.

## Fluxo de uso

1. Usuário abre a pasta; sem manifesto, confirma inicializar.
2. Consulta ou edita um item pelo app, CLI ou MCP.
3. A operação persiste no projeto; o app reflete alterações externas.
4. Ao reabrir, os registros são recuperados do disco.

## Regras e limites atuais a revisar

Manifesto, .vibedeck/, IDs, autoria e formatos são contratos candidatos à preservação. A migração não deve tratar um arquivo existente como descartável nem confundir estado temporário de UI com dado do projeto.

## Direção desejada já registrada

Core Rust compartilhado entre interfaces. Instalação mínima e uso multiplataforma são metas confirmadas; armazenamento em outro formato ou serviço central não foi solicitado.

## Decisões para o usuário

Revisar se todo dado deve continuar local e versionável; política de edição simultânea, backups, recuperação de arquivos inválidos e requisitos de um projeto recém-criado.

## Cenário de aceite proposto

AC-001: criar um item em projeto temporário, reler em outra interface e obter os mesmos ID e conteúdo. Falha de escrita não deve deixar JSON parcial.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/ProjectStore.swift](../../../../Sources/VibeDeckCore/ProjectStore.swift)
- [Sources/VibeDeckCore/Models.swift](../../../../Sources/VibeDeckCore/Models.swift)
- [Sources/VibeDeckCore/FileWatcher.swift](../../../../Sources/VibeDeckCore/FileWatcher.swift)
- [Package.swift](../../../../Package.swift)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).

## Mudança confirmada — MUD-001: início guiado

Ao começar um projeto no VibeDeck, guiar o usuário perguntando stack e padrões. Detectar skills, agentes e comandos existentes no projeto e perguntar se quer cadastrá-los no VibeDeck; a detecção não autoriza cadastrar automaticamente.
Fluxo, cenários e questões sobre primeira abertura, pular/retomar e duplicatas estão no [registro da decisão](../07-mudancas-confirmadas.md). Pedido ainda não implementado.
