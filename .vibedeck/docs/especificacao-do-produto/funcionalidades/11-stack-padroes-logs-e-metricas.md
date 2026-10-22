---
author: ai
---
# FUN-011 — Stack, padrões, configuração e diagnóstico

# FUN-011 — Stack, padrões, configuração e diagnóstico

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Stack registra tecnologias com notas/tags e catálogo de ícones; mantém badge no README. Padrões possuem regras e escopo e geram tópicos vinculados por sourcePattern. IA consulta stack/padrões sob demanda.
Configurações de provider/modelo e execução distinguem projeto e máquina. Diagnóstico registra ações/relações e falhas; logs ficam fora do projeto, sem conteúdo de prompts/documentos. CLI/MCP permitem consultar logs.
Consumo de IA e limites são recursos diferentes: métricas registram uso informado nas operações e limites dependem do provider/conta. Leitura sob demanda e snapshots de contexto reduzem repetição; não existe garantia fixa de economia por tarefa.

## Fluxo de uso

1. Definir stack e padrões do projeto.
2. Consultá-los antes de implementar.
3. Verificar regras associadas à mudança.
4. Inspecionar ação/erro por diagnóstico e uso por métricas, quando disponível.

## Regras e limites atuais a revisar

Badge não contém todas as notas/regras; tags não definem escopo. Consultar padrões não garante cumprimento: checks e revisão continuam necessários. Logs não são destino para prompts ou segredos.

## Direção desejada já registrada

Manutenibilidade e baixo custo de contexto são metas expressas. Aprovação na primeira tentativa e poucos tokens são indicadores desejados, não SLA nem promessa existente.

## Decisões para o usuário

Revisar catálogo, atualização automática do README, tópicos vinculados, métricas úteis e quais configurações são compartilháveis versus locais.

## Cenário de aceite proposto

AC-011: adicionar padrão liga tópico consultável; remover segue contrato de vínculo. Consulta de métricas/logs não expõe conteúdo dos documentos/prompts.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/Stack.swift](../../../../Sources/VibeDeckCore/Stack.swift)
- [Sources/VibeDeckCore/Patterns.swift](../../../../Sources/VibeDeckCore/Patterns.swift)
- [Sources/VibeDeckCore/Logging.swift](../../../../Sources/VibeDeckCore/Logging.swift)
- [Sources/VibeDeckCore/AIUsage.swift](../../../../Sources/VibeDeckCore/AIUsage.swift)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).

## Cadastro concreto deste projeto — 22/10/2026

Stack: Swift, Apple, Cloudflare Workers, TypeScript, Rust, MCP e Zod.
Padrões: TDD, SOLID, Injeção de dependência, Núcleo funcional, Clean Code, Desenvolvimento orientado a comportamento, Design por contrato, Clean Architecture, DDD, Repository, Serviço de domínio, Objeto de valor, Strategy, Factory, Builder, Adapter, Decorator, Observer, Command, State e Singleton.
Todos estão com paths vazio (escopo global), totalizando 57 regras. Notas da stack, texto integral das regras, severidades, IDs, tópicos e mapa proposto de aplicação ao Core estão em [08 — Stack e padrões](../08-stack-e-padroes-do-projeto.md).
Esse cadastro descreve as escolhas do projeto, sem provar conformidade do código existente. O papel do Zod está pendente porque não há nota de uso no registro. Os dados devem ser relidos no MCP antes de executar a refatoração.
