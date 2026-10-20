---
author: ai
---
# Worker de schemas: endpoints, cache e CORS

Complementa o guia de execução, que só cita o comando de deploy do Worker. Este documento descreve o comportamento do código do Worker.

Fontes: `worker/src/index.ts`, `worker/wrangler.jsonc`, `worker/package.json`, `scripts/set-schema-url.sh`, `schema/v1/`.

## Visão geral

- O projeto Worker se chama `vibedeck-schema` (`worker/wrangler.jsonc:3`, `worker/package.json:2`). O ponto de entrada é `src/index.ts` (`worker/wrangler.jsonc:4`).
- O Worker serve os JSON Schemas do VibeDeck (`worker/src/index.ts:1`).
- Os arquivos estáticos vêm do diretório `./public`, ligado ao binding `ASSETS`. Com `run_worker_first: true`, o código do Worker roda antes dos assets (`worker/wrangler.jsonc:6-10`).
- O `compatibility_date` é `2026-10-01` (`worker/wrangler.jsonc:5`).

## Scripts npm

Os scripts estão em `worker/package.json:5-10`.

| Script | O que faz |
|---|---|
| `sync` | Apaga `public`, recria o diretório e copia `../schema/v1` para `public/v1`. |
| `dev` | Roda `sync` e depois `wrangler dev`. |
| `deploy` | Roda `sync` e depois `wrangler deploy`. |
| `typecheck` | Roda `tsc --noEmit`. |

O `public/` é gerado pelo `sync`, a partir de `schema/v1/`. A edição dos schemas deve ser feita em `schema/v1/`.

Dependências de desenvolvimento: `@cloudflare/workers-types`, `typescript` e `wrangler`, com as versões de `worker/package.json:11-15`.

## Comportamento HTTP

Todo o código está em `worker/src/index.ts:11-52`.

- **`OPTIONS`**: responde 204 sem corpo, com cabeçalhos CORS (linha 13).
- **Outros métodos além de `GET` e `HEAD`**: respondem 405 `Method Not Allowed` (linhas 14-16).
- **`/`, `/v1` e `/v1/`**: respondem um JSON com `name: "VibeDeck schemas"` e um mapa `schemas`. As URLs são montadas a partir da origem da requisição mais `/v1/` (linhas 19-38).
- **Demais caminhos**: o Worker busca o arquivo no `ASSETS`. Se a resposta não for `ok`, devolve 404 `Not Found` (linhas 41-42).
- **CORS**: todas as respostas citadas acima levam `Access-Control-Allow-Origin: *` e `Access-Control-Allow-Methods: GET, HEAD, OPTIONS` (linhas 6-9, 44-45).
- **Arquivos `*.schema.json`**: recebem `Content-Type: application/schema+json; charset=utf-8` e `Cache-Control: public, max-age=86400, stale-while-revalidate=604800`. O comentário no código diz que os caminhos versionados são append-only (linhas 46-50).

## Schemas listados no índice

O índice lista dez chaves (`worker/src/index.ts:24-35`). Cada uma tem um arquivo correspondente em `schema/v1/`:

| Chave do índice | Arquivo |
|---|---|
| `project` | `project.schema.json` |
| `reviewGroup` | `review-group.schema.json` |
| `ruleTopic` | `rule-topic.schema.json` |
| `idea` | `idea.schema.json` |
| `agent` | `agent.schema.json` |
| `command` | `command.schema.json` |
| `skill` | `skill.schema.json` |
| `workflow` | `workflow.schema.json` |
| `workflowRun` | `workflow-run.schema.json` |
| `ruleCheck` | `rule-check.schema.json` |

A lista de arquivos existentes em `schema/v1/` foi conferida e coincide com as dez chaves.

## Trocar a URL base dos schemas

`scripts/set-schema-url.sh <url-base-sem-/v1>` faz o seguinte:

1. Exige o argumento e remove a barra final (linhas 6-7).
2. Lê a URL antiga da linha `public static let base` de `Sources/VibeDeckCore/Models.swift` (linha 8).
3. Substitui a URL antiga pela nova em `Sources`, `schema` e `README.md`, usando `sed -i ''` (linha 9). Essa forma de `sed` é a do macOS.
4. Imprime `Schema base: <antiga> → <nova>` (linha 10).

O script não faz deploy. O deploy é feito antes, com `npm run deploy` em `worker/`.