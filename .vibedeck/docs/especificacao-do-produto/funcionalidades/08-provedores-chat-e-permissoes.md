---
author: ai
---
# FUN-008 — Provedores, chat e permissões

# FUN-008 — Provedores, chat e permissões

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Os provedores implementados são Claude e Codex (AIProvider). O painel usa transportes específicos e mantém provider/sessão por conversa. Trocar provider inicia outra conversa; isso não equivale a transferir automaticamente todo o estado anterior.
O painel apresenta ferramentas, planejamento, perguntas, aprovações e interrupção. Há comandos/skills por /, referências por @ e acesso a terminal. Configurações explícitas de modelo/effort são respeitadas; indisponibilidade não causa troca automática.
No Codex, Planejar é somente leitura; Editar projeto permite escrita dentro das permissões. Operações de descoberta/geração de propostas são somente leitura; geração de testes e implementação têm autorização própria.

## Fluxo de uso

1. Selecionar provider disponível e contexto do projeto.
2. Iniciar conversa ou tarefa com modo/permissões.
3. Responder perguntas, revisar plano e aprovar quando exigido.
4. Acompanhar ferramentas/saída e cancelar ou retomar conforme a operação.

## Regras e limites atuais a revisar

Instalação e autenticação do provider são pré-requisitos atuais das funções de IA. Dados do projeto continuam consultáveis sem executar LLM. Nunca substituir provider/modelo explicitamente escolhido em silêncio.

## Direção desejada já registrada

A visão humana inclui alternar provedores e menciona OpenCode. OpenCode é desejo de expansão, não suporte implementado. Continuidade entre providers ainda precisa de definição.

## Decisões para o usuário

Revisar persistência de conversas, modos de permissão, aprovação automática, continuidade entre provedores e quais integrações entram na primeira versão.

## Cenário de aceite proposto

AC-008: modelo/effort incompatível informa erro sem fallback; trocar provider não altera o provider de uma execução existente; proposta somente leitura não modifica o projeto.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/AIProvider.swift](../../../../Sources/VibeDeckCore/AIProvider.swift)
- [Sources/VibeDeckCore/AIIntegration.swift](../../../../Sources/VibeDeckCore/AIIntegration.swift)
- [Sources/VibeDeckCore/AIConversationTransport.swift](../../../../Sources/VibeDeckCore/AIConversationTransport.swift)
- [Sources/VibeDeckCore/CodexRPC.swift](../../../../Sources/VibeDeckCore/CodexRPC.swift)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).
