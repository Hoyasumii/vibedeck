---
author: ai
---
# Geração de documentos, grafo e eficiência de IA

Fontes: `README.md:174`, `README.md:181-208`, `README.md:351-387`, `.vibedeck/AGENTS.md`.

## Gerar documentos

- Disponível na lista de **Docs** quando há Claude Code ou Codex instalado. A geração é somente leitura, com cancelamento e timeout de 180 segundos por chamada (`README.md:174`).
- São propostos até 8 documentos. Campos vazios e conteúdos acima de 40.000 caracteres são descartados (`README.md:174`).
- Nada é gravado em `.vibedeck/docs` antes do aceite. O aceite cria Markdown com `author: ai` e slugs únicos, e vale um único passo de undo (`README.md:174`).
- Leitura: `vibedeck docs cat` e MCP `read_doc`. Criação com autoria de IA: `vibedeck docs new "Título" --body "..." --ai` e MCP `write_doc` com `generated: true` (`README.md:174`).

## Grafo

- Recursos locais, começa por comunidades, com até 180 nós e 300 relações por vista (`README.md:181-182`).
- **Gerar** e **Atualizar** rodam estrutura de código e análise semântica com o provedor selecionado. Não iniciam ao abrir a aba. Há uma execução por projeto (`README.md:183-185`).
- O JSON e o HTML só são publicados após validação, preservando o resultado anterior em falhas (`README.md:185-186`).
- Exportação offline sem IA: `vibedeck graph export` ou MCP `export_graph` (`README.md:186-187`).
- Validação do renderer: `node scripts/test-graph-renderer.cjs` (`README.md:187`).
- O `AGENTS.md` do repositório orienta usar `graphify query` quando `graphify-out/graph.json` existir e rodar `graphify update .` após modificar código (`AGENTS.md`, seção graphify).

## Painel IA

- Atalho ⇧⌘C. Claude usa `claude -p` em stream-json, Codex usa `codex app-server --stdio` (`README.md:188-189`).
- Cada conversa mantém seu provedor e sessão. Trocar de provedor cria uma nova conversa (`README.md:191-192`).
- `/` lista comandos e skills, `@` lista arquivos e conversas, `!` roda comando de terminal (`README.md:199-201`).
- Terminal interativo (⌃`) com SwiftTerm, cada aba numa sessão própria (`README.md:202-207`).

## Eficiência e consumo de IA

- O guia inicial `.vibedeck/AGENTS.md` traz as obrigações; `.vibedeck/guide.md` guarda a referência completa. Prompts personalizados não são reescritos (`README.md:353-357`).
- Leitura sob demanda: `vibedeck ai guide` e depois `--section <n>`; `vibedeck ai catalog <tipo>` com `--offset` e `--limit` (`README.md:358-360`).
- Conversas referenciadas grandes viram snapshots locais imutáveis, lidos por trechos com `vibedeck ai context <id> --offset 0 --limit 4000` (`README.md:361-364`).
- Métricas: `vibedeck ai usage --json`; `--clear` limpa só as métricas. Caracteres não são tokens, e não há estimativa de preço (`README.md:374-377`).
- Não há envio de telemetria, e os registros de consumo não guardam o texto dos prompts (`README.md:380-382`).
- `scripts/test-ai-efficiency.sh` testa a economia do contexto inicial, com meta de pelo menos 30% em cenários redundantes. O README ressalta que não há promessa de economia fixa por tarefa (`README.md:384-387`).