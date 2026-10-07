# VibeDeck — guia para agentes de IA

Este diretório é gerenciado pelo app **VibeDeck**. Ele guarda links, documentos e
pontos de revisão do projeto em arquivos locais que você (agente) pode ler e editar.

## Estrutura

```
vibedeck.json                 # declara o projeto: nome, links, tipos de revisão (reviewKinds)
.vibedeck/
  AGENTS.md                   # este arquivo (regenerado pelo app; não edite)
  docs/<slug>.md              # documentos markdown (título = frontmatter `title:` ou primeiro `# `)
  reviews/<slug>.json         # um grupo (tema) de itens de revisão por arquivo
```

Schemas: https://vibedeck-schema.SUBDOMAIN.workers.dev/v1/project.schema.json e https://vibedeck-schema.SUBDOMAIN.workers.dev/v1/review-group.schema.json

## Itens de revisão

Cada item de `reviews/*.json` descreve algo a ajustar no projeto
("inativar esse botão", "isso não precisa aparecer agora"):

- `kind`: um dos `reviewKinds` do vibedeck.json (padrão: disable, hide, fix, change, remove, note)
- `status`: open | in_progress | done | wontfix
- `priority`: low | normal | high
- `target` (opcional): `file`, `route`, `component`, `selector` — onde no código/app
- `author`: human | ai

## Regras para agentes

1. Prefira o CLI (`vibedeck ...`) ou o servidor MCP (`vibedeck mcp`) em vez de editar o JSON à mão.
   Se editar à mão, siga o schema e mantenha ids (UUID) e datas ISO 8601.
2. Itens criados por você devem ter `author: "ai"`.
3. Ao começar um item, marque `in_progress`; ao concluir, `done`. Não apague itens de humanos.
4. Antes de mexer em uma área, leia os itens abertos que apontam para ela.

## Comandos úteis

```sh
vibedeck status                              # resumo do projeto
vibedeck review list --status open --json    # itens abertos
vibedeck review add "Tela de login" --kind hide "Esconder link de cadastro" --file src/Login.tsx --ai
vibedeck review set <id> --status done       # id completo ou prefixo (>= 4 chars)
vibedeck docs list | vibedeck docs cat <slug>
```

MCP: `claude mcp add vibedeck -- vibedeck mcp`
