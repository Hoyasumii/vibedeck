# CORE F01 — Formato de dados em disco (contrato para o Core Rust)

Base: análise estática de `Sources/VibeDeckCore/*.swift` (Models, ProjectStore, ItemGroups, Rules, RuleTests, RuleExecution, WorkflowRuns, Workflows, Agents, Commands, Skills, Stack, Patterns, PortableSHA256, FileWatcher), `schema/v1/*.schema.json` e os dados reais deste repo (`vibedeck.json`, `.vibedeck/**`). Decisões aplicadas: D11 (paridade total de dados), D5 (nuvem removida/limpa), D4 (Docs com symlinks relativos).

Verificações empíricas feitas nos dados reais (reproduzíveis com o emissor do Apêndice A):
- 464 de 466 arquivos `.json` (vibedeck.json + `.vibedeck/**`) são reproduzidos **byte a byte** por um emissor genérico (parse → chaves ordenadas → serialização do Apêndice A). As 2 exceções são dados auxiliares escritos à mão em `.vibedeck/tests/` (`melhorar-o-md-viewer/results.json`, `aumentar-o-catalogo-de-padroes/catalog-before-expansion.json`), não gerenciados pelo Core.
- Os mesmos 464 validam sem erro contra `schema/v1` com o mini-validador `.vibedeck/tests/geral/_validate.py` (escopo completo, incluindo subpastas, `checks/` e `runs/`).
- `Rule.contentHash` confere nas 302 regras com script (nenhuma `stale`). `Idea.contentFingerprint` confere em 16 das 19 ideias com `readiness` (as 3 restantes divergem; compatível com edição posterior, que o próprio Core trata como "verificação velha", mas não investiguei).
- Todo UUID gravado nos dados está em MAIÚSCULAS (0 minúsculos).

## 0. Cobertura (critério de pronto)

| Item | Seção |
|---|---|
| Schemas v1 (10): project, review-group, rule-topic, idea, agent, command, skill, workflow, workflow-run, rule-check | §3.1 a §3.10 |
| `vibedeck.json` | §3.1 |
| `.vibedeck/agents` `commands` `skills` `workflows` | §3.6 a §3.8 |
| `.vibedeck/ideas` `reviews` `rules` | §3.2 a §3.4 |
| `.vibedeck/checks` `runs` | §3.9, §3.10, §4 |
| `.vibedeck/docs` `attachments` | §3.11, §3.12 |
| `.vibedeck/tests` | §5.6 |
| `.vibedeck/AGENTS.md` `guide.md` | §3.13 |

## 1. Layout

```
<raiz>/vibedeck.json                      manifesto (Project). Marca a raiz; `find` sobe diretórios até achá-lo.
<raiz>/.vibedeck/
  AGENTS.md  guide.md                     gerados (AgentsGuide). Não editar à mão.
  docs/<grupo/...>/<slug>.md              Markdown (frontmatter opcional). Recursivo.
  reviews/<grupo/...>/<slug>.json         ReviewGroup (um "tema" por arquivo). Recursivo.
  rules/<grupo/...>/<slug>.json           RuleTopic. Recursivo.
  ideas/<grupo/...>/<slug>.json           Idea. Recursivo.
  skills/<grupo/...>/<slug>.json          Skill. Recursivo.
  agents/<slug>.json                      Agent. PLANO (não recursivo).
  commands/<slug>.json                    Command. PLANO.
  workflows/<slug>.json                   Workflow. PLANO.
  checks/<yyyyMMdd-HHmmss>-<id8>.json     RuleCheck (histórico imutável, só-adição).
  runs/<slug-workflow>/<run>/run.json     WorkflowRun + arquivos livres das etapas (plano.md, revisao.md, outputs/...).
  attachments/<owner>-<nome>[-n].<ext>    binários coladas/importados.
  tests/<slug-topico>/<id8>.sh (+ _lib.sh, helpers)   scripts de regras; criados por quem gera o teste (IA/humano), não pelo Core.
```

Contagem neste repo: agents 12, commands 13, skills 6, workflows 5, rules 48, ideas 43 (6 em subpastas `criacao-do-core/`, `arquitetura-e-desempenho/`), reviews 8, checks 324, runs 4 `run.json`, docs 34 `.md` (subpastas), attachments 2, tests 323 arquivos em 25 pastas.

`ensureDirectories()` cria, com `createDirectory(withIntermediateDirectories)`: docs, reviews, rules, ideas, agents, commands, skills, workflows, checks, attachments (NÃO cria `tests/` nem `runs/`; criados sob demanda por `AtomicFile.write`, que cria o diretório pai).

Quem lê o quê:
- `listRecords` (reviews, rules, ideas, skills = recursivo; agents, commands, workflows = só o diretório): só arquivos regulares `*.json` (extensão comparada em minúsculas), ignora ocultos (`.x`), **ignora symlinks** (arquivo ou diretório; não desce), valida contenção de cada arquivo. Arquivo que não decodifica é **ignorado com aviso de log** (`store.decode_skipped`), nunca erro. Ordem: `(createdAt, slug)` crescente (createdAt com precisão de segundos; empate pelo slug com `<` de String).
- `listDocs`: `*.md` recursivo, mesma regra de ocultos/symlinks; ordem por título com `localizedStandardCompare` (ordem "natural" da localidade; difícil de reproduzir 1:1).
- `listChecks`: `checks/*.json` (não recursivo, ocultos fora), que decodificam; ordem mais novo primeiro por `(createdAt, mtime do arquivo)`.
- `listRuns`: para cada diretório de `runs/` (nomes que não começam com `.`) e cada subdiretório, lê `run.json` se existir e decodificar; ordem `(updatedAt, ref)` decrescente. Diretórios que não são run (ex.: `runs/mestre-12/logs`) são ignorados em silêncio.

## 2. Convenções globais (valem para todos os JSON)

### 2.1 Configuração exata do encoder (arquivos)
`VDJSON.encoder` = `JSONEncoder` com `outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, `dateEncodingStrategy = .iso8601`, demais opções padrão. `VDJSON.encode(_:)` = `encoder.encode(value)` + um único byte `0x0A` no fim. Todo arquivo de registro (project, groups, topics, ideas, agents, commands, skills, workflows, runs, checks) passa por aí.

Saída resultante (confirmada nos 464 arquivos):
- UTF-8, sem BOM, LF, **exatamente um `\n` final** (nenhuma linha em branco extra).
- Indentação de **2 espaços** por nível.
- Separador chave/valor **`" : "`** (espaço, dois-pontos, espaço): `"id" : "…"`.
- Vírgula no fim da linha do elemento (`,\n`), sem vírgula final.
- **Chaves de objeto em ordem crescente** (bytes UTF-8; todas as chaves do modelo são ASCII; `$schema` vem primeiro porque `$` < letras; maiúscula antes de minúscula: `ruleId` < `rules`... não ocorre no mesmo objeto, mas a regra é a ordem de bytes).
- **Contêiner vazio**: `[` `\n` linha vazia (sem espaços) `\n` indentação do nível + `]`. Exemplo no nível 1: `  "failures" : [\n\n  ],`. Objeto vazio: por simetria `{\n\n<ind>}` (**não verificado**; nenhum `{}` nos dados).
- Strings: `"` e `\` escapados; `\n \r \t \b \f` em forma curta; demais controles < 0x20 como `\u00xx` com **hex minúsculo** (`\u001b`, confirmado em checks com saída ANSI); **`/` nunca escapado**; não-ASCII (acentos, `→`, emoji, U+2009) gravado cru em UTF-8. Não verificado: tratamento de U+007F, U+2028/2029 (esperado: crus).
- Inteiros sem sinal `+`/ponto/expoente. Booleanos `true`/`false`. Nulos **nunca** emitidos (opcionais ausentes são omitidos; ver 2.3).
- Datas: `Date` → string ISO 8601 UTC **sem frações**, `yyyy-MM-ddTHH:mm:ssZ` (fração truncada, não arredondada). **Única exceção**: `RuleCheck.createdAt` grava milissegundos com `Z`: `2026-10-09T03:17:31.836Z` (`Date.ISO8601FormatStyle(includingFractionalSeconds: true)`, 3 dígitos).
- UUID: `UUID.uuidString` = 36 caracteres **MAIÚSCULOS** com hífens. A leitura aceita maiúsculas e minúsculas; a gravação normaliza para maiúsculas.

Variante compacta (`VDJSON.compactEncoder`: `[.sortedKeys, .withoutEscapingSlashes]`, sem `\n` final, `"k":v` sem espaços) é só saída para agentes (`rules_for`, planos); **não** grava arquivo.

`VDJSON.encodeObject(_ :Any)` (JSONSerialization com `[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]` + `\n`) é usado em um único lugar: reescrever referências `{"kind":"skill","ref":...}` em agents/commands/skills/workflows quando uma skill é movida/renomeada (`referenceUpdates`). Preserva chaves desconhecidas (é a única via que não perde campos). A formatação de contêineres vazios e números do JSONSerialization pode diferir do JSONEncoder: **não verificada**. No Rust, usar o mesmo emissor do §2.1 e só reescrever o arquivo se o valor mudou (Swift compara com `NSDictionary.isEqual`).

### 2.2 Decoder
`VDJSON.decoder` = `JSONDecoder` com data customizada: tenta `Date(s, strategy: .iso8601)` e depois `ISO8601FormatStyle(includingFractionalSeconds: true)`; senão erro. Rust: aceitar RFC 3339 com `Z` (com ou sem fração; sugiro aceitar também deslocamento `±hh:mm`), emitir sempre UTC `Z`.

Todos os modelos têm `init(from:)` tolerante: campos ausentes recebem default (tabelas abaixo). Chaves desconhecidas são **ignoradas** (e portanto **perdidas** na próxima gravação tipada; ver risco R2).

### 2.3 Regras de emissão
- Opcional ausente (`nil`) → chave omitida.
- Vários arrays/strings são omitidos quando vazios (`if !x.isEmpty`); outros são sempre gravados mesmo vazios (como `[\n\n]`). Cada tabela abaixo marca: **sempre** (S), **omitido se vazio/nil** (O).
- Enums gravados pelo `rawValue` (`in_progress`, `wontfix`...).

### 2.4 Escrita atômica
`AtomicFile.write(data, to:)`: sob um `NSLock` global de processo (`RemoteWorkspace.filesLock`), `createDirectory(pai, withIntermediateDirectories: true)` e `Data.write(to:, options: .atomic)` (arquivo temporário no mesmo diretório + `rename`). Depois registra log (`VDLog.fileWritten`, em `~/Library/Application Support/VibeDeck/logs`, fora do projeto). Não há `fsync` explícito, nem lock entre processos (app, CLI e MCP concorrentes → "última escrita vence", sem merge). Remoção: `ProjectFiles.remove` (removeItem sob o mesmo lock); mover: `moveItem`.
Rust: temp no mesmo diretório + `rename` (permissão 0644 sob umask), mutex de processo, criar pais. Atenção: `rename` sobre um symlink o **substitui** (ver §6, D4).

### 2.5 Slugs (nome de arquivo) — `Slug.make(text)`
1. Dobra o texto com `.diacriticInsensitive` e `.caseInsensitive` (locale `en_US_POSIX`): remove acentos, minúsculas (folding Unicode, p.ex. `ß`→`ss`).
2. Percorre os escalares: mantém só **ASCII alfanumérico** (`[a-z0-9]` após o folding); qualquer outro caractere vira **um** `-` (consecutivos colapsam; nunca começa com `-`).
3. Remove `-` finais **antes** de truncar; depois trunca em **60 caracteres** (`prefix(60)`). Logo um slug pode terminar em `-` após o corte (ex.: `criar-agentes-comandos-skills-e-workflows-pre-definidos-que-` nos dados reais).
4. Vazio → `untitled`.
`uniqueSlug(base, dir, ext)`: se `base.ext` existe → `base-2`, `base-3`, ... (para runs, `ext` vazio = diretório).
Criação com `reference` (caminho com grupos, p.ex. `criacao-do-core/minha-ideia`): cada componente passa por `Slug.make` (`normalizedGroupPath`).
Agents, commands, workflows: slug = `Slug.make(title)` + `uniqueSlug`.
Anexos: `Slug.make(owner) + "-" + Slug.make(nome sem extensão)` + sufixo único + `.` + `Slug.make(extensão)`. O link Markdown é `![nome](../attachments/<arquivo>)` (imagem: png, jpg, jpeg, gif, webp, heic, svg, tif, tiff, bmp) ou `[nome](…)`, com `../` repetido uma vez por componente do `owner` (`attachmentPath`); `[` e `]` do nome viram `(` e `)`. Ex. real: `painel-lateral-melhorado-captura-de-tela-2026-10-09-as-13-06-47.png`.

### 2.6 Resolução de referências (`resolveSlug`)
Slug (ou apenas o último componente), `Slug.make(ref)` do último componente, **prefixo de id ≥ 4 caracteres** (comparação em minúsculas; prefixo ambíguo → erro `ambiguousReference`), id completo, título (comparação case-insensitive). Referência com `/` é caminho exato; se o arquivo não existe, tenta título e nunca cai para slug "solto". Rule: id completo ou prefixo ≥ 4 (`matchRule`). Idea/Run: id/prefixo conforme `resolveRunRef` (`<workflow>/<run>`, nome único de run, ou id/prefixo ≥ 4).

### 2.7 Validação de caminhos gerenciados (`validatedRecordURL`, `containedURL`)
- `normalizedGroupPath(ref)`: rejeita vazio, `/` inicial, `\`, componentes vazios, `.`, `..` ou que começam com `.` → `invalidGroupPath`. (A **validação** não reescreve a referência: `validatedRecordURL` normaliza só para validar e usa o texto original + `.ext`.)
- `containedURL`: resolve symlinks do diretório do conceito e exige que esteja dentro de `canonical(.vibedeck)`; resolve o caminho final (inclusive o maior ancestral existente, para criações) e exige que fique dentro do diretório do conceito. Symlink pendente/que escapa → `invalidGroupPath`.
- Validação aplicada em: docs, reviews, rules, ideas, skills (leitura, escrita, apagar, mover). **Agents, commands e workflows NÃO validam** (`agentURL(slug)` direto); como o slug vem de `Slug.make`, não há travessia na prática. O Rust deve validar todos (superconjunto seguro).
- Enumeração nunca segue symlinks e pula ocultos.
- Mover/renomear grupo ou item: valida todos os descendentes antes, recusa destino existente (`groupConflict`), e para o conceito `skills` reescreve referências (`kind:"skill"`, `ref`) em agents/commands/skills/workflows com rollback dos bytes se algo falhar. Apagar grupo não vazio exige confirmação.

### 2.8 Nuvem (D5)
Único dado estruturado: `Project.codexCloudEnvironment` (string, opcional; ausente neste repo). Rust: **ignorar na leitura, nunca emitir** (limpa o campo na próxima gravação). Textos sobre nuvem em `guide.md`/`AGENTS.md` (seção "Sessões na nuvem"), em `docs/sessoes-na-nuvem-e-limites-de-uso.md`, em regras/ideias (`worker-e-schemas`, `build-scripts-e-ci`, 5 ideias de `ideas/criacao-do-core/`) e em 27 checks são **conteúdo livre**: checks são histórico imutável (não tocar). Decisão pendente para o coordenador: apagar ou não o doc de nuvem (é conteúdo de usuário/IA; recomendo só remover as seções geradas do guia e o campo).

## 3. Registros

Legenda: **Req** = o decoder lança erro se ausente; **Def** = default do decoder; **Emit** = S sempre / O omitido se vazio-nil. Ordem de chaves em disco é sempre a alfabética (a ordem das tabelas segue o `CodingKeys` só por leitura).

### 3.1 `vibedeck.json` — Project (schema `project`)
Arquivo: `<raiz>/vibedeck.json`. Escrita: `saveProject` (leitura-modifica-grava sem cache).
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional (`nil` se ausente no arquivo; novo projeto = `…/v1/project.schema.json`) | O (só se existe) |
| `version` | int | Def 1 | S |
| `id` | UUID | Def **novo UUID aleatório a cada leitura** até salvar | S |
| `name` | string | **Req** | S |
| `description` | string | opcional | O |
| `links` | [Link] | Def [] | **S** (mesmo vazio) |
| `claude` | [ClaudeItem] | Def [] | O |
| `stack` | [StackItem] | Def [] | O |
| `patterns` | [ProjectPattern] | Def [] | O |
| `codexCloudEnvironment` | string | opcional | **removido (D5)** |
| `reviewKinds` | [ReviewKind] | Def = os 6 padrões se ausente **ou vazio** | S |

- `Link {id UUID (Def novo), title string (Def = url), url string Req, tags [string] O}`.
- `ClaudeItem {id UUID (Def novo), title (Def = último componente da URL ou "claude.ai"), url Req, kind "artifact"|"doc" (Def artifact), tags O, addedAt data (Def agora)}`; todos emitidos exceto tags vazias. URL só é aceita na criação se `http(s)` e host `claude.ai` sem usuário/senha (`ClaudeItem.accepts`).
- `StackItem {icon string Req (identidade), name (Def = icon) S, category O, note (omitida se vazia), tags O, author (Def human) S}`; ordem do array = ordem de exibição.
- `ProjectPattern {id Req, name (Def = id) S, category O, summary (omitido se vazio), note (idem), topic O (slug do tópico em rules/), tags O, author (Def human) S}`. `category` ∈ practices, architecture, domain, design, custom.
- `ReviewKind {id, label, symbol?}`; defaults: `disable/Inativar/nosign`, `hide/Ocultar/eye.slash`, `fix/Corrigir/wrench.and.screwdriver`, `change/Alterar/pencil`, `remove/Remover/trash`, `note/Nota/note.text`.
- Exemplo real: chaves em disco `$schema, id, links, name, patterns, reviewKinds, stack, version` (21 patterns, 7 stack items, 6 kinds).

### 3.2 `reviews/<slug>.json` — ReviewGroup (`review-group`)
Slug: `Slug.make(title)` ou referência com grupos; `uniqueSlug`. Escrita validada.
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `title` | string | **Req** | S |
| `description` | string | opcional | O |
| `tags` | [string] | Def [] | O |
| `createdAt` | data | Def agora | S |
| `items` | [ReviewItem] | Def [] | **S** |

`ReviewItem`: `id` (Def novo) S; `kind` string (Def `note`; qualquer string é aceita) S; `title` Req S; `details` O; `status` open|in_progress|done|wontfix (Def open) S; `priority` low|normal|high (Def normal) S; `target` {file,route,component,selector — todos opcionais, cada um O} O (o construtor normaliza alvo vazio para nil); `rules` [slugs de tópicos] O; `author` human|ai (Def human) S; `createdAt` (Def agora) S; `updatedAt` (Def = createdAt) S. `updateItem` carimba `updatedAt = agora`. Busca de item: id completo ou prefixo ≥ 4 em todos os grupos. `ensureVerified`: ver §5.5.

### 3.3 `rules/<slug>.json` — RuleTopic (`rule-topic`)
Slug: `Slug.make(title)` + `uniqueSlug` (criação não aceita grupos; subpastas existem e são lidas).
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `title` | string | **Req** | S |
| `author` | human\|ai | Def **human** | **S** |
| `description` | string | opcional | O |
| `tags` | [string] | Def [] | O |
| `paths` | [glob] | Def [] (vazio = tópico global) | O |
| `rules` | [Rule] | Def [] | **S** |
| `sourceIdea` | UUID | opcional | O |
| `sourcePattern` | string (id do padrão em vibedeck.json) | opcional | O |
| `createdAt` | data | Def agora | S |

`Rule`: `id` (Def novo) S; `text` Req S; `group` O (caminho aninhado dentro do tópico; passa por `normalizedGroupPath`, só organização); `details` O; `severity` must|should (Def must) S; `author` (Def human) S; `createdAt` (Def agora) S; `test` O.
`RuleTest`: `mode` script|manual (Def: `script` se há `command`, senão `manual`); `command` O; `reason` O; `ruleHash` string (Def `""`); `generatedAt` (Def agora); todos sem omissão exceto `command`/`reason` quando nil. O `RuleTest` não tem `encode` customizado (síntese: opcionais nil omitidos).
- `contentHash` = `hex(SHA-256(UTF8(text + "\n" + (details ?? ""))))` dos **8 primeiros bytes** = 16 hex minúsculos (sem normalização/trim). `testState`: sem `test` → `none`; `ruleHash != contentHash` → `stale`; `mode==script` e `command` não vazio após trim → `script`; senão `manual`. `scriptCommand` = command (trim) só no estado `script`; `needsAgent` = estado ≠ script.
- `setRuleTest`: `command` trimado, `reason` trimado ou nil, `ruleHash = contentHash` atual, `generatedAt = agora`; `mode=script` exige command. `clearRuleTest`/`deleteRule` apagam o script gerado apenas se o comando não tem espaços e resolve para dentro de `.vibedeck/tests/`.
- Aplicabilidade: global (paths vazio) ∪ tópicos citados explicitamente (slug/id/título) ∪ tópicos cujo glob casa algum arquivo tocado (`Glob`, §5.4). Ordem = ordem de `listTopics`.
- Apagar tópico: remove o arquivo e roda `releaseOrphanedIdeas` e `releaseOrphanedPatterns` (despromove ideias; remove padrões cujo tópico sumiu).
- Padrões do catálogo criam tópico `Padrão: <nome>` com tag `padrao`, `sourcePattern=id`, regras do template com UUIDs novos (catálogo embutido: 32 templates em `Patterns.swift`; Rust precisa embutir o mesmo texto).

### 3.4 `ideas/<grupo/>/<slug>.json` — Idea (`idea`)
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `title` | string | **Req** | S |
| `body` | string (Markdown) | opcional | O |
| `status` | new\|exploring\|approved\|discarded\|done | Def new | S |
| `tags` | [string] | Def [] | O |
| `paths` | [glob] | Def [] | O |
| `rules` | [Rule] (rascunho) | Def [] | **S** |
| `promotedTopic` | string (slug) | opcional | O |
| `readiness` | IdeaReadiness | opcional; **`try?`: valor malformado é descartado em silêncio** | O |
| `dependencies` | [UUID] | Def [] (decoder **remove duplicatas** mantendo a 1ª) | O |
| `author` | human\|ai | Def human | S |
| `createdAt` | data | Def agora | S |
| `updatedAt` | data | Def = createdAt | S |

`IdeaReadiness {viable bool (Def false) S; missing [string] O; checkedAt data (Def agora) S; fingerprint string (Def "") S}`.
`contentFingerprint` = 16 hex minúsculos (8 primeiros bytes de SHA-256) de `join([title, body ?? "", join(paths, "\n")] + regras.map("\(severity)\t\(text)\t\(details ?? "")"), separador "\n\u{1F}\n")`.
Regras de negócio com efeito no disco: `promoteIdea` (cria/sincroniza tópico com `sourceIdea=idea.id`, descrição `Regras vindas da ideia "<título>".`, status vira `approved` se não fechado), `unpromote` (apaga tópico, `promotedTopic=nil`, `approved`→`exploring`), `setIdeaDependencies` (valida: sem auto-referência, UUID existente, sem ciclo). `updateX` sempre carimba `updatedAt = agora`.

### 3.5 (reservado: `Rule` e `RuleTest` estão em §3.3)

### 3.6 `agents/<slug>.json` — Agent (`agent`)
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `title` | string | **Req** | S |
| `summary` | string | opcional | O |
| `model` | string | opcional | O |
| `providerSettings` | {provedor: {model?, effort?}} | opcional | O |
| `tools` | [string] | Def [] | O |
| `prompt` | string | Def `""` | **S** |
| `nextSteps` | [NextStep] | Def [] | O |
| `tags` | [string] | Def [] | O |
| `author` | human\|ai | Def human | S |
| `createdAt` | data | Def agora | S |
| `updatedAt` | data | Def = createdAt | S |

`NextStep {kind agent|command|skill (Def agent) S; ref string Req S (slug do agente/comando/skill do VibeDeck); note O}`. `providerSettings` é um dicionário `String → {model?, effort?}`; chaves de provedor usadas: `claude`, `codex` (o JSON ordena as chaves).
Regras: `addNextStep` resolve o alvo para slug, rejeita o próprio dono, ignora duplicata `(kind, ref)`. Importação de `.claude/agents/*.md` (frontmatter `name, description, model, tools`; corpo = prompt; tag `claude-code`).

### 3.7 `commands/<slug>.json` — Command (`command`)
Igual a Agent, com `argumentHint` (string O) entre `summary` e `model`. Importação de `.claude/commands/**/*.md` (subpastas viram `ns:nome`; frontmatter `description, argument-hint, allowed-tools, model`).

### 3.8 `skills/<grupo/>/<slug>.json` (`skill`) e `workflows/<slug>.json` (`workflow`)
Skill = Agent + `sourcePath` (string O; caminho **absoluto** do `SKILL.md` importado, dependente da máquina; importação de `.claude/skills/<nome>/SKILL.md`). Recursivo, validado; criação aceita grupos.
Workflow:
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `title` | string | **Req** | S |
| `summary`, `input` | string | opcionais | O |
| `maxSteps` | int | opcional (guarda: execução usa `max(1, maxSteps ?? 25)`) | O |
| `steps` | [WorkflowStep] | Def [] | O |
| `tags` | [string] | Def [] | O |
| `author` | enum | Def human | S |
| `createdAt` / `updatedAt` | data | Def agora / = createdAt | S |

`WorkflowStep {id string (Def = ref; trim; vazio → ref) S; kind (Def agent) S; ref Req S; note O; maxVisits int O (decoder descarta valores ≤ 0); transitions [WorkflowTransition] O}`.
`WorkflowTransition {verdict O, when O, to Req S}` (decoder: `verdict` e `when` com trim, vazio → nil). Uma transição sem `verdict` e sem `when` é o "senão" e fica sempre por último (`addTransition`); só uma por etapa. Ids de etapa únicos: `newStepId` = `Slug.make(base)`, `-2`, `-3`.
Casamento de veredito (`normalize`): trim + remove os caracteres `` ` * _ . `` das pontas + dobra caixa e diacríticos.

### 3.9 `checks/<yyyyMMdd-HHmmss>-<id8>.json` — RuleCheck (`rule-check`)
Nome: `createdAt` formatado em **GMT**, `Calendar gregoriano`, locale `en_US_POSIX`, campos `yyyy` `MM` `dd` `-` `HH` (24h) `mm` `ss` (a data é truncada em segundos) + `-` + **8 primeiros caracteres do id em minúsculas** + `.json`. Ex.: `20261009-031731-e876c608.json` ⇔ `createdAt` `2026-10-09T03:17:31.836Z`, `id` `E876C608-…`. Se dois checks caem no mesmo segundo com ids de prefixo distinto, nomes distintos (o Core não trata colisão do mesmo nome; probabilidade ínfima).
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional (novo = `…/rule-check.schema.json`) | O |
| `id` | UUID | Def novo | S |
| `task` | string | Def `""` | S |
| `files` | [string] relativos à raiz, **únicos e ordenados** (`Set` → `sorted`) | Def [] | S |
| `topics` | [string] slugs aplicáveis, na ordem de `listTopics` | Def [] | S |
| `reviewItem` | UUID | opcional | O |
| `results` | [RuleResult] | Def [] | S |
| `passed` | bool | Def false | S |
| `warnings` | [string] | Def [] | S |
| `failures` | [string] | Def [] | S |
| `pending` | [string] | Def [] | O |
| `author` | human\|ai | Def **ai** | S |
| `createdAt` | **string** ISO 8601 com milissegundos | Def agora | S |

`RuleResult {topic string Req S; ruleId UUID Req S; verdict pass|fail|na Req S; note O; source agent|script (Def agent; **omitido quando agent**) ; exitCode int32 O}`.
Para `source=script`, `note` = `"<comando> (exit <código>)\n<saída>"` com trim de espaços/quebras nas pontas; ex. real: `".vibedeck/tests/geral/9d6f362b.sh (exit 0)\n(sem saída)"`. Ordem de `results` = ordem das regras candidatas (tópicos aplicáveis, depois regras do arquivo) que têm resposta.
`passed = !(existe regra must com verdict fail)`; `failures` = textos das regras must que falharam; `warnings` = textos das should que falharam + `"Teste desatualizado (a regra mudou): <texto>"` para toda candidata `stale`; `pending` = textos das regras de agente (sem script atual) sem resposta.
Checks são **só-adição**: nunca editados nem apagados (regra `geral/9D6F362B`). `completeRuleExecution` (UI) grava com `task = "Verificação de regras pelo aplicativo"`, `author = ai` e exige que as regras não tenham mudado.

### 3.10 `runs/<workflow>/<run>/run.json` — WorkflowRun (`workflow-run`)
Diretório da run: `Slug.make(input)` (60 chars; reiniciar com a mesma entrada retoma a run) ou, sem input, `uniqueSlug("execucao-" + Slug.make(<UTC yyyy-MM-ddTHH:mm:ss>))` (sem exemplo no repo). Ex. real: `ideia-e8cbf97f-9556-44a5-8271-8eaa61030cb3-implemente-consul`. A pasta guarda também arquivos livres das etapas (`plano.md`, `revisao.md`, `outputs/`); o Core não os interpreta (apagar a run remove a pasta inteira).
| Chave | Tipo | Req/Def | Emit |
|---|---|---|---|
| `$schema` | string | opcional | O |
| `id` | UUID | Def novo | S |
| `workflow` | string (slug) | **Req** | S |
| `provider` | claude\|codex | Def claude | **S** |
| `input` | string | opcional | O |
| `status` | running\|waiting\|done\|stopped | Def running | S |
| `current` | string (id da etapa) | opcional (ausente quando terminou) | O |
| `reason` | string | opcional | O |
| `cycle` | int | Def 1 | **S** |
| `checkpoint` | {step S, verdict O, output S, completed bool S} | opcional | O |
| `history` | [WorkflowRunEntry] | Def [] | O |
| `questions` | [WorkflowQuestion] | Def [] | O |
| `createdAt` / `updatedAt` | data | Def agora / = createdAt | S |

`WorkflowRunEntry {step Req S; verdict O (trim, vazio→nil); summary O (idem); next O; cycle int (Def 1) S; at data (Def agora) S}` — `cycle` e `at` sempre gravados (codificação sintetizada).
`WorkflowQuestion {number int Req S; step Req S; question Req S; context O; options [{label S, description O}] (Def []) **S sempre**; multiple bool (Def false) **S sempre**; answer O; createdAt (Def agora) S; answeredAt O}`.
Máquina de estados (`WorkflowRunEngine`, pura): `record` escolhe transição por `to` explícito → veredito → condições (`decide`) → "senão"; depois aplica guardas: `maxSteps` (parada), `maxVisits` da próxima etapa, "voltou para si com o mesmo veredito" (parada) ; `ask` cria perguntas numeradas e põe `waiting`; `answer` volta a `running` quando não há aberta; `stop` põe `stopped` com `reason` (padrão `parada pelo usuário`). Mensagens `reason` em pt-BR fazem parte do dado (copiar literalmente do código).
Esta é a única persistência de run: ordem de listagem `(updatedAt, ref)` desc.

### 3.11 Docs — `docs/<grupo/>/<slug>.md`
Markdown livre, UTF-8, sem formato de encoder. `slug` = caminho relativo sem `.md`. Criação (`createDoc`): conteúdo `[frontmatter] + "# <título>\n\n<corpo>"`, frontmatter `---\nauthor: ai\n---\n` só quando `author=ai`. Frontmatter tolerante (não é YAML real): `title:` (aspas `"` `'` e espaços aparados), `tags: [a, b]` ou `tags: a, b`, `author: ai`. Título exibido = `title:` do frontmatter, senão a 1ª linha que começa com `# `, senão o slug. `setDocTags` reescreve só a linha `tags:` (removida se vazio): linhas do frontmatter sem `tags:` + `tags: [a, b]` **no fim**; se o frontmatter ficar vazio, ele some; sem frontmatter prévio, cria `---\ntags: [..]\n---\n` + corpo. Todo o resto é preservado (split por `\n`, sem normalizar `\r\n`). Neste repo: 34 docs, todos começam com `---`.

### 3.12 `attachments/` — ver §2.5. Escrita atômica; nome único por `uniqueSlug`.

### 3.13 `AGENTS.md` e `guide.md` (gerados)
`writeAgentsGuide` grava `AgentsGuide.markdown` em `.vibedeck/AGENTS.md` e `referenceMarkdown` em `.vibedeck/guide.md`; `refreshAgentsGuideIfNeeded` compara **bytes** e reescreve se diferirem (em `initialize`, abertura pelo app/CLI). Texto embutido no Swift (`AgentsGuide.swift`, 421 linhas, com trechos interpolados: `SchemaURL.base`, `AIPromptPolicy.instructions`, índice de seções). O Rust precisa de **uma** fonte de texto; enquanto Swift e Rust coexistirem, versões diferentes disputariam o arquivo. Seções de nuvem saem (D5), então a paridade byte a byte do guia é uma **exceção declarada**. `.vibedeck/AGENTS.md` ≠ `<raiz>/AGENTS.md` (este é do repositório, não gerado pelo Core).

## 4. Como checks e runs são gravados (resumo operacional)
1. `submitCheck`/`completeRuleExecution` → `saveRuleCheck` monta o `RuleCheck`, `ensureDirectories`, `AtomicFile.write(VDJSON.encode(check), checks/<nome>.json)`. Nunca reescreve um check existente.
2. Run: `startRun` cria/retoma; cada mutação (`record`, `ask`, `answer`, `stop`, checkpoint) faz ler-modificar-gravar `run.json` inteiro via `saveRun` (`updatedAt` carimbado pela engine).
3. Leitura de histórico de gate: `verificationProblems(for: item)` usa o **primeiro** check de `listChecks()` (mais novo) com `reviewItem == item.id`; exige `passed`, e que toda regra atual dos tópicos requeridos esteja em `results`; regras novas sem resposta → problema; regra manual obrigatória (must) sem resposta → problema; manual `should` sem resposta é tolerada.

## 5. Execução de regras de script

### 5.1 O que vira trabalho
Somente regras no estado `script` (`scriptCommand != nil`). Regras `stale` **não rodam** (viram `warnings`); `manual`/`none` precisam de resposta do agente (`pending` se faltar). Respostas de agente para regra de script são ignoradas.

### 5.2 Processo (`ShellRunner.run`, `RuleTestRunner.live`)
- Executável: `$SHELL` se definido, senão `/bin/zsh` (macOS) ou `/bin/sh` (demais). Argumentos: `["-lc", <comando>]` (shell de **login**, não interativo; o comando é interpretado pelo shell, pode ter pipes e aspas).
- `cwd` = raiz do projeto (`root.standardizedFileURL`, sem resolver symlinks).
- `stdin` = `/dev/null`. `stdout` e `stderr` no **mesmo pipe** (ordem de intercalação preservada).
- Ambiente = ambiente atual do processo + `VIBEDECK_ROOT` (caminho da raiz; num workspace remoto, o caminho remoto), `VIBEDECK_FILES` (arquivos da tarefa, relativos, únicos e ordenados, separados por `\n`; **vazio** quando não há arquivos — scripts tratam vazio como "verifique tudo"), `VIBEDECK_RULE_ID` (UUID maiúsculo), e `VIBEDECK_ACTION` se há ação de log ativa (somente telemetria).
- Timeout: **120 s** desde o início do processo (não conta fila). Ao estourar: `SIGTERM` no shell e em todos os descendentes (varredura recursiva por `pgrep -P`, **não** `SIGKILL`); código forçado **124**; texto ganha `Tempo esgotado (120 s).` em linha própria.
- Cancelamento externo: mesmo término em árvore, código **130**, texto `Cancelado.`; se já cancelado antes de iniciar, nem inicia (`Cancelado.`, 130). Falha ao lançar: `Não foi possível executar: <erro>`, código **127**.
- Saída: bytes → String UTF-8 com substituição de inválidos; `trim` de espaços e quebras nas pontas; se `count` (caracteres/grafemas) > **4000**: `"… (saída cortada)\n" + últimos 4000 caracteres` (mantém o fim); se vazio: `(sem saída)`. Término por sinal não capturado: `terminationStatus` = número do sinal.
- Nota do check (`source=script`): `"\(comando) (exit \(código))\n\(saída)"` com trim.

### 5.3 Veredito
`exit 0` → **pass**; `exit 77` → **na** ("não se aplica aos arquivos tocados"); qualquer outro (incl. 124, 127, 130, sinais) → **fail**. `exitCode` é gravado. Convenção dos scripts: `exit 77` quando `VIBEDECK_FILES` não vazio e nenhum arquivo casa o escopo da regra (helper `applies` em `_lib.sh`).

### 5.4 Paralelismo e ordem
- Limite = `clamp(solicitado ?? núcleos_ativos, 1, núcleos_ativos)` (`ProcessInfo.activeProcessorCount`). Cada script roda numa thread dedicada.
- **Travas de ferramenta de build** (`BuildToolLock`): scripts que invocam a mesma ferramenta (chaves `swift`, `node`, `cargo`, `go`, `gradle`, `maven`, `dotnet`, `composer`, `make`, detectadas por regex sobre o comando e sobre o conteúdo de arquivos `.sh`/`.py` referenciados, seguindo referências recursivamente só dentro da raiz, ignorando linhas de comentário `#`) nunca rodam juntos; esperar a trava não ocupa vaga. Porte a tabela de regex literalmente.
- Resultados voltam na **ordem de declaração** (tópicos aplicáveis, regras na ordem do arquivo). Eventos `started`/`finished` serializados, `started` antes de `finished` por regra.
- `submitCheck` (CLI/MCP) roda todos os scripts mesmo após falha `must`; só o fluxo do app aceita `stopOnMustFailure`/cancelamento (nenhum novo script inicia; os em andamento só terminam em cancelamento).
- Glob de escopo (`Glob.matches`): trim; vazio → falso; remove `./` inicial; `/` inicial ancora na raiz, senão padrão **sem `/`** vira `**/<padrão>`; `/` final → `**` depois; `*` = `[^/]*`; `?` = `[^/]`; `**/` = `(?:.*/)?`; `**` = `.*`; `. + ( ) ^ $ | [ ] { } \` literais; casamento ancorado `^…$`, sensível a caixa (ICU/NSRegularExpression).

### 5.5 Gates ligados ao dado
`ReviewItem` com regras só vai a `done` se o último check do item passou e respondeu todas as regras do escopo (`rulesNotVerified`). Escopo = `rules` explícitos do item + tópicos que casam `target.file` + globais.

### 5.6 `.vibedeck/tests/`
Convenção `tests/<slug-do-tópico>/<id8-minúsculo-da-regra>.sh`; o caminho vai em `rule.test.command` (relativo à raiz, sem espaços). O Core só apaga o script se está sob `tests/`. A pasta também contém `_lib.sh`, `_validate.py` e dados auxiliares escritos à mão (sem contrato). Neste repo: 302 regras com script (todas `.vibedeck/tests/…sh`), 13 manuais, 97 sem teste; 126 scripts não precisam de Swift (python3/grep/git), 176 usam `swift build/test`.

## 6. Symlinks em Docs (D4) — contrato proposto
Hoje: **todo symlink é ignorado** em listagem/escrita/mover (`recordFiles`) e `containedURL` recusa alvo fora de `.vibedeck/docs`. D4 exige exceção explícita só para o conceito `docs`:
1. Vínculo = symlink **relativo** `docs/<slug>.md` → `../../<ARQUIVO>.md` apontando para `.md` regular **na raiz** do projeto (ex.: `README.md`, `AGENTS.md`). Colisão de slug com doc existente → sufixo `-raiz`.
2. Listagem: incluir o symlink como doc (slug = nome do link) se o alvo resolvido é arquivo regular `.md` cujo pai é a raiz; alvo quebrado → entrada com aviso (e opção de remover o vínculo); alvo fora da raiz/fora do projeto, encadeado ou em diretório symlink → **nunca seguir** (ignorar com aviso).
3. Escrita: gravar **no alvo** (resolver antes do `rename` atômico). `Data.write(.atomic)`/`rename` sobre o caminho do link o substituiria por arquivo comum.
4. Apagar/mover um doc vinculado remove/renomeia o **link**, nunca o alvo.
5. Rastrear `canonical(url)` evita dupla listagem (hoje `relativeRecordPath` canoniza; com o link o slug deve vir do nome do link, não do alvo).

## 7. Divergências schema/v1 × código × dados

| # | Divergência | Efeito |
|---|---|---|
| S1 | `rule-topic.author` não é obrigatório no schema, mas `RuleTopic.encode` sempre grava (`Def human`). **15 de 48 tópicos** deste repo não têm `author` (vão ganhar `"author" : "human"` na primeira gravação tipada). | round-trip tipado ≠ identidade; fixtures "sem diff" só valem para leitura/cópia crua |
| S2 | Schema exige `severity`, `author`, `createdAt` em `rule`; decoder tolera (must/human/agora). `createdAt` ausente = relógio da leitura | instável até salvar |
| S3 | Schema exige `test.ruleHash` e `test.generatedAt`; decoder aceita sem (`ruleHash=""` ⇒ `stale`; `mode` deduzido de `command`). `command` vazio passa o decoder (schema: `minLength 1`) | teste escrito à mão lê como desatualizado |
| S4 | `providerSettings`: schema só admite chaves `claude`/`codex` (`additionalProperties:false`); código aceita qualquer chave (`[String: AIProviderSettings]`) | Rust: mapa livre |
| S5 | `idea.readiness`: schema exige `viable`, `checkedAt`, `fingerprint`; decoder usa defaults e **descarta o objeto inteiro se malformado** (`try?`) | perda silenciosa ao salvar |
| S6 | `idea.dependencies[]`: pattern do schema aceita hex minúsculo; código grava maiúsculo e deduplica ao ler | normaliza |
| S7 | `workflow.maxSteps`/`step.maxVisits`: schema `minimum 1`; decoder descarta `maxVisits ≤ 0` e aceita `maxSteps` qualquer (engine usa `max(1, …)`). `step.id` ausente/vazio = `ref` | |
| S8 | `workflow-run`: `provider` e `cycle` opcionais no schema, sempre gravados; `history[].cycle/at`, `questions[].options/multiple` sempre gravados (codificação sintetizada) | campos "obrigatórios de fato" |
| S9 | `project`: schema exige `version`/`id`; decoder gera `id` **novo a cada leitura** se ausente e substitui `reviewKinds` vazio pelos 6 padrões | |
| S10 | `pattern.category` no schema cita "practices, architecture, domain or custom"; catálogo/código também usa `design` (`PatternCategory.all`). Sem `enum`, não quebra | texto do schema desatualizado |
| S11 | `reviewKind.id` (pattern `^[a-z0-9_-]+$`), `link.url` (`format: uri`): o código não valida. `ReviewItem.kind` aceita qualquer string; só o validador Python confere contra `reviewKinds` | |
| S12 | `rule-check.createdAt`: schema só diz `date-time`; o código usa milissegundos aqui e segundos em tudo mais | contrato implícito |
| S13 | Escopo do script `geral/9F92A765` (validação contra schema): só arquivos de 1º nível (`.vibedeck/{reviews,rules,ideas,agents,commands,skills,workflows}/*.json` + `vibedeck.json`). **Não cobre** subpastas (6 ideias em subpastas), `checks/` nem `runs/`. Verifiquei que todos passam validando com escopo total | lacuna do gate, não dos dados |
| S14 | Sem schema: frontmatter dos docs, `AGENTS.md`, `guide.md`, `tests/*.sh`, `attachments/`, arquivos livres das runs, `sourcePath` (absoluto) | formatos ad hoc descritos neste documento |
| S15 | `$schema` só é gravado na criação; o decoder mantém ausente se o arquivo não tinha (nenhum caso neste repo) | |
| S16 | `Link.url` e `ClaudeItem.url`: o schema de `claudeItem.url` restringe host `claude.ai`; o decoder não revalida (só `ClaudeItem.make/accepts`) | |
| S17 | Código escreve `agents/commands/workflows` sem `validatedRecordURL` (só skills/ideas/reviews/rules/docs validam) | |

## 8. Riscos de paridade

R1. **Emissor**: reproduzido por regra simples (Apêndice A, 464/466 arquivos), mas dependem de implementação Foundation: objeto vazio `{}`, U+007F, U+2028/9, e a saída de `JSONSerialization` (`encodeObject`) não têm exemplo nos dados.
R2. **Chaves desconhecidas**: a decodificação tipada do Swift as descarta; um Rust que as preserve diverge (mais seguro, menos "paridade"); um que as descarte perde dados. Decisão necessária; recomendo: operação sem alteração nunca regrava o arquivo, e gravações tipadas seguem o Swift (descartam), com aviso de log.
R3. **Normalização na regravação** (S1, S2, S6, S9, `reviewKinds`, UUID minúsculo→maiúsculo, datas fracionárias→segundos, `tags: []` removidos): o Core Rust deve normalizar igual ao primeiro `save` Swift. Fixtures de round-trip devem separar "arquivo intocado" de "arquivo regravado".
R4. **Tempo**: o Swift mantém `Date` com sub-segundo em memória e grava truncado; ordens e `updatedAt` iguais em segundos empatam pelo slug/mtime. `.now` como default de campos ausentes torna a leitura não determinística. `RuleCheck` é o único com ms. Fuso GMT/POSIX fixos no nome do check.
R5. **Slug**: `Slug.make` depende do folding Unicode da Foundation (caixa e diacríticos). Para pt-BR (acentos comuns) basta NFD + descartar marcas + `to_lowercase`; letras como `ß`, `ø`, `ł`, ligaturas e compatibilidades (`ª`, `º`) podem divergir: criar testes com todos os títulos/nomes reais do repo (slugs dos arquivos de `.vibedeck/**` e dos anexos) e casos de borda; aceitar divergência só fora do repertório pt/en.
R6. **Ordenação**: docs por `localizedStandardCompare` (numérica, locale); demais por `(createdAt, slug)`. Reproduzir a primeira exige regra "natural" explícita (documentar a escolhida).
R7. **Glob/regex**: ICU vs `regex` do Rust (anchors, classes); porte para um matcher próprio com testes tabelados a partir de `Glob.regex`.
R8. **Shell**: `-lc` com `$SHELL` herda o PATH do perfil de login; em Linux mínimo `pgrep` pode não existir (os descendentes ficariam vivos segurando o pipe até acabarem). Rust: usar grupo de processos (`setsid` + `killpg`) é mais robusto mas mata mais do que o Swift. Truncamento por **grafemas**, não por bytes/`char`. Intercalação stdout/stderr exige **um** pipe.
R9. **Sem trava entre processos**: app, CLI e MCP seguem "última escrita vence"; um Rust que adicione locks muda o comportamento (provavelmente desejável; registrar).
R10. **Conteúdo embutido**: catálogo de padrões (32), catálogo de kits (`KitCatalog.swift`), `AgentsGuide` e mensagens pt-BR (`VibeDeckError`, `reason` das runs) fazem parte do dado gravado/impresso; precisam ser copiados literalmente ou extraídos para um arquivo único consumido pelos dois lados. Skill Icons exige rede (worker externo).
R11. **Symlinks** (D4) contradizem a regra atual "nunca seguir"; a implementação deve ser um caso especial testado contra travessia (`..`, links encadeados, alvo fora da raiz, alvo em diretório-link).
R12. **Caminhos absolutos** no dado: `skill.sourcePath`, `VIBEDECK_ROOT`, texto `Recursos da skill: <dir>` no prompt de etapas; fixtures movidas de máquina não reproduzem bytes de saída.
R13. **Plataforma**: `Process.terminationStatus` por sinal, shell padrão (`/bin/zsh` vs `/bin/sh`), login shell e `Date.formatted` se comportam diferente em macOS/Linux; testes de paridade devem rodar nas duas.
R14. Leitura tolerante: arquivo que não decodifica é **ignorado** na listagem (com log) mas **erro** no `load`; o Rust deve reproduzir essa assimetria.

## 9. Piloto DEC-005 — 5 regras (pass, fail, não-aplicável)

Critérios: script existente em `.vibedeck/tests/`, sem `swift build/test`, sem rede, determinístico, com `exit 77` por `VIBEDECK_FILES` ou falha reproduzível por mutação em cópia (fixture). O runner Rust deve executar o **mesmo script** e gravar um check cujo `results[]` coincide com o do Swift (exceto `id`, `createdAt`, nome do arquivo). Verifiquei estaticamente os resultados abaixo executando cada script só-leitura na raiz atual.

| # | Regra (id completo) | Tópico / script | Sev. | pass (`VIBEDECK_FILES`) | na (77) | fail (1) |
|---|---|---|---|---|---|---|
| 1 | `9F92A765-76E7-4EA0-A66A-78AE12EE4C8F` JSON do projeto segue o schema | `geral` · `.vibedeck/tests/geral/9f92a765.sh` (+ `_validate.py`) | must | vazio ou `vibedeck.json` → exit 0 | `README.md` → 77 | em cópia, acrescentar `"bogus":1` a `.vibedeck/reviews/abas.json` e `VIBEDECK_FILES=.vibedeck/reviews/abas.json` → exit 1, saída `…abas.json: $: chave desconhecida 'bogus'` + `violação: JSON fora do schema (veja acima)` (confirmado) |
| 2 | `0A89A5BC-A21B-465C-AE44-9099C3D77A9B` `$id` dos schemas = `SchemaURL.base` | `worker-e-schemas` · `.vibedeck/tests/worker-e-schemas/0a89a5bc.sh` | must | vazio ou `schema/v1/idea.schema.json` → 0 | `README.md` → 77 | em cópia, trocar o `$id` de `idea.schema.json` → exit 1 (confirmado): `schema/v1/idea.schema.json: $id = '…example.com…', esperado '…'` |
| 3 | `57ADA275-8A0F-42BA-9E14-BA3B34AB8235` `RuleCheck.createdAt` com frações; nome do arquivo `yyyyMMdd-HHmmss-<id8>` em GMT | `core-e-formato-de-dados` · `…/57ada275.sh` | must | vazio ou `Sources/VibeDeckCore/Rules.swift` → 0 | `README.md` → 77 | em cópia, remover `includingFractionalSeconds: true` de `Rules.swift` → exit 1 (mensagem do script; previsto, não executado) |
| 4 | `DFE3361B-6AFE-4ED3-A741-4FC0818D197D` URL dos schemas só muda via `set-schema-url.sh` | `core-e-formato-de-dados` · `…/dfe3361b.sh` | **should** | vazio ou `README.md` → 0 | `vibedeck.json` → 77 | em cópia, trocar a base num `*.schema.json` → exit 1; como é `should`, o check deve sair `passed=true` com o texto da regra em `warnings` (cobre a semântica de severidade) |
| 5 | `AC4BA963-CDEE-419C-B057-9140643E115D` não apagar itens/regras/ideias de humanos | `geral` · `…/ac4ba963.sh` (usa `git diff`/`git show` read-only) | must | qualquer `VIBEDECK_FILES` → 0 (sem `applies`, nunca é na) | — | em repo git temporário: remover um objeto `author:"human"` de uma ideia e não confirmar → exit 1 com `<arquivo>: objeto human <id> foi removido`. **Evidência real**: `checks/20261009-171554-769c7b4e.json` (fail, exit 1) |

Evidência histórica no repo (mesmos ids, `source=script`): pass `checks/20261009-000436-062feea4.json` (regras 1 e 5), na `checks/20261009-011351-4e5d23f1.json` (regra 1), na `checks/20261009-023103-b3cdef2f.json` (regra 3), na `checks/20261011-184120-93bc967d.json` (regra 4), na/pass da regra 2 em `checks/20261014-000641-6162022b.json` / `checks/20261009-123224-d8ee0b27.json`. Formato de `note` esperado: `.vibedeck/tests/<tópico>/<id8>.sh (exit N)\n<saída ou "(sem saída)">`.

Se forem só 4 regras, tirar a nº 5 (depende de git). Complementos de conformidade do **runner** (não são regras do repo; testes sintéticos): timeout (124 com `Tempo esgotado (120 s).`, usando limite injetável), exit 2 e exit 127 → `fail`, saída > 4000 caracteres (`… (saída cortada)`), saída vazia (`(sem saída)`), `VIBEDECK_FILES` com vários arquivos ordenados, ordem dos resultados com paralelismo > 1, e trava `cargo` entre dois scripts.

Observação: as regras 3 e 4 inspecionam código Swift; quando `VibeDeckCore` for removido (D12) precisarão ser reescritas contra o Rust. Para o piloto de paridade valem enquanto o Swift existe.

## Apêndice A — Emissor de referência (reproduz 464/466 arquivos)

```python
def esc(s):
    o = ['"']
    for ch in s:
        c = ord(ch)
        if ch == '"': o.append('\\"')
        elif ch == '\\': o.append('\\\\')
        elif ch == '\n': o.append('\\n')
        elif ch == '\r': o.append('\\r')
        elif ch == '\t': o.append('\\t')
        elif ch == '\b': o.append('\\b')
        elif ch == '\f': o.append('\\f')
        elif c < 0x20: o.append('\\u%04x' % c)      # hex minúsculo
        else: o.append(ch)                           # '/' e não-ASCII crus
    o.append('"'); return ''.join(o)

def enc(v, d=0):
    p = '  ' * d
    if isinstance(v, dict):
        if not v: return '{\n\n' + p + '}'           # (não verificado)
        items = sorted(v.items(), key=lambda kv: kv[0].encode('utf-8'))
        return '{\n' + ',\n'.join(p + '  ' + esc(k) + ' : ' + enc(x, d + 1) for k, x in items) + '\n' + p + '}'
    if isinstance(v, list):
        if not v: return '[\n\n' + p + ']'
        return '[\n' + ',\n'.join(p + '  ' + enc(x, d + 1) for x in v) + '\n' + p + ']'
    if v is True: return 'true'
    if v is False: return 'false'
    if isinstance(v, str): return esc(v)
    return str(v)                                    # inteiros

# arquivo = (enc(obj) + '\n').encode('utf-8')
```
Isto valida só a camada de formatação. A camada tipada (quais chaves omitir, defaults, normalização) está nas tabelas do §3.
