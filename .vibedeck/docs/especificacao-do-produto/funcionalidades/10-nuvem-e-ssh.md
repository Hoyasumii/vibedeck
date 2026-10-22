---
author: ai
---
# FUN-010 — Execução local e projetos SSH

# FUN-010 — Execução local e projetos SSH

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado — nuvem a retirar

Sessões na nuvem são iniciadas por ação explícita. O fluxo atual verifica sincronização da branch padrão com origin após fetch; divergência bloqueia e alterações não commitadas exigem confirmação. Codex Cloud exige ambiente configurado.
Nuvem e SSH são funções distintas. Em SSH, o app conecta ao servidor, navega no projeto, mantém cache e sincroniza alterações. Há trabalho offline, reconexão e resolução explícita de conflitos. IA, regras e terminal executam no servidor; provider instalado só no Mac não basta.
O MCP stdio precisa de executável disponível no ambiente em que o cliente inicia o processo. Ter configuração no repositório não prepara sozinho a máquina de nuvem.

## Fluxo atual — a etapa de nuvem será removida

1. Nuvem: verificar branch/estado, confirmar e iniciar tarefa no provider escolhido.
2. SSH: autenticar e conferir identidade do host, selecionar pasta e confirmar inicialização se necessária.
3. Editar/sincronizar; resolver conflitos antes de novas ações de IA/regras.
4. Usar terminal remoto para ferramentas/autenticação do servidor.

## Regras e limites atuais a revisar

Não iniciar sessão remota sem pedido. Não instalar/trocar provider automaticamente. Chave de host alterada bloqueia; conflitos não são resolvidos descartando dados silenciosamente.

## Direção desejada já registrada

Decisão confirmada em 22/10/2026: remover a funcionalidade de sessões de nuvem. Manter apenas execução local e por SSH. MCP portátil por stdio permanece, sem requisito de sessão de nuvem.

## Decisões para o usuário

SSH permanece. Definir transição dos comandos/configurações de nuvem, preservação de dados antigos e preparação dos ambientes local/SSH. Transporte HTTP remoto não foi solicitado.

## Cenário de aceite proposto

AC-FUN010: fluxo mínimo MCP funciona localmente/em máquina limpa e via SSH; conflitos SSH preservam versões até decisão. O produto deixa de oferecer criação de sessões de nuvem.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/CloudSession.swift](../../../../Sources/VibeDeckCore/CloudSession.swift)
- [Sources/VibeDeckCore/SSHConnection.swift](../../../../Sources/VibeDeckCore/SSHConnection.swift)
- [Sources/VibeDeckCore/RemoteWorkspace.swift](../../../../Sources/VibeDeckCore/RemoteWorkspace.swift)
- [Sources/VibeDeckCore/RemoteExecution.swift](../../../../Sources/VibeDeckCore/RemoteExecution.swift)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).

## Pedido confirmado — MUD-003

O histórico acima descreve o código atual e ajuda a inventariar a retirada. Não é requisito para manter nuvem. Consultar [mudanças confirmadas](../07-mudancas-confirmadas.md) antes de implementar.
