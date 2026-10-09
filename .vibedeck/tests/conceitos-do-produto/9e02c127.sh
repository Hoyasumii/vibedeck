#!/usr/bin/env bash
# Dados do projeto vivem em vibedeck.json + .vibedeck/: sem banco nem estado oculto; todo campo persistido
# está no schema e todo diretório/schema está descrito no AGENTS.md (AgentsGuide.swift).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/|^schema/"; then exit 77; fi
python3 -I - <<'PY'
import re, glob, json, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
core = {f: open(f).read() for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift"))}
allsrc = {f: open(f).read() for f in sorted(glob.glob("Sources/**/*.swift", recursive=True))}
models = core["Sources/VibeDeckCore/Models.swift"]
urls = dict(re.findall(r'public static let (\w+) = "\\\(base\)/([\w-]+\.schema\.json)"', models))
schemas = {}
for name, fn in urls.items():
    p = f"schema/v1/{fn}"
    try: schemas[name] = (p, json.load(open(p)))
    except FileNotFoundError: fail(f"Sources/VibeDeckCore/Models.swift: SchemaURL.{name} aponta para {p}, que não existe")
    except ValueError as e: fail(f"{p}: JSON inválido ({e})")
def keys_of(block): return [k.split("=")[0].strip() for k in block.replace("\n", " ").split(",") if k.strip()]
# 1. Registros de primeiro nível: todo CodingKey está em properties do schema.
for f, s in core.items():
    for m in re.finditer(r'case schema = "\$schema", ([^\n]+)', s):
        line = s[:m.start()].count("\n") + 1
        before = s[:m.start()]
        st = list(re.finditer(r"public struct (\w+)", before))[-1].group(1)
        sm = re.search(r"self\.schema = SchemaURL\.(\w+)", s[before.rfind("public struct " + st):])
        if not sm or sm.group(1) not in schemas:
            fail(f"{f}:{line}: {st} é gravado com $schema mas não usa um SchemaURL com arquivo em schema/v1"); continue
        path, sch = schemas[sm.group(1)]
        props = sch.get("properties", {})
        for k in ["$schema"] + keys_of(m.group(1)):
            if k not in props: fail(f"{path}: campo \"{k}\" de {st} ({f}:{line}) não está descrito no schema")
# 2. Tipos aninhados: todo CodingKey aparece no schema do arquivo que os guarda.
nested = {"ReviewItem": "reviewGroup", "ReviewTarget": "reviewGroup", "Rule": "ruleTopic", "RuleTest": "ruleTopic",
          "Link": "project", "ReviewKind": "project", "StackItem": "project", "ProjectPattern": "project",
          "RuleResult": "ruleCheck"}
for st, sname in nested.items():
    for f, s in core.items():
        m = re.search(r"public struct %s\b[^{]*\{" % st, s)
        if not m: continue
        rest = s[m.end():]
        nxt = re.search(r"\npublic (struct|enum|final class|class|extension) ", rest)
        body = rest[:nxt.start()] if nxt else rest
        ck = re.search(r"enum CodingKeys: String, CodingKey \{\s*case ([^}]+?)\s*\}", body) or \
             re.search(r"enum CodingKeys: String, CodingKey \{\s*\n\s*case ([^\n]+)", body)
        if not ck or sname not in schemas: continue
        path, sch = schemas[sname]
        text = json.dumps(sch)
        for k in keys_of(ck.group(1)):
            if f'"{k}"' not in text: fail(f"{path}: campo \"{k}\" de {st} ({f}) não está descrito no schema")
# 3. AGENTS.md descreve cada diretório de .vibedeck/ e lista cada schema.
guide = core["Sources/VibeDeckCore/AgentsGuide.swift"]
store = core["Sources/VibeDeckCore/ProjectStore.swift"]
for var, d in re.findall(r'public var (\w+Dir): URL \{ dataDir\.appending\(path: "([\w-]+)"', store):
    if not re.search(r"^\s+%s/" % re.escape(d), guide, re.M):
        fail(f"Sources/VibeDeckCore/AgentsGuide.swift: diretório .vibedeck/{d}/ ({var}) não está descrito no AGENTS.md")
lst = re.search(r"Schemas: \\\(SchemaURL\.base\)/\{([^}]*)\}\.schema\.json", guide)
listed = set(lst.group(1).split(",")) if lst else set()
for name, fn in urls.items():
    if fn.removesuffix(".schema.json") not in listed:
        fail(f"Sources/VibeDeckCore/AgentsGuide.swift: schema {fn} não está listado no AGENTS.md")
if "vibedeck.json" not in guide: fail("Sources/VibeDeckCore/AgentsGuide.swift: AGENTS.md não descreve o vibedeck.json")
# 4. Sem banco de dados nem persistência oculta de dados do projeto.
for f, s in allsrc.items():
    for i, l in enumerate(s.split("\n")):
        if re.match(r"\s*import (SQLite3?|CoreData|SwiftData|GRDB|RealmSwift|Realm)\b", l):
            fail(f"{f}:{i+1}: banco de dados ({l.strip()}): dados do projeto devem ficar em arquivos do repo")
# Estado fora do repo só para preferências de UI e dados da máquina (chats/uso de IA, terminal, cache de ícones).
LOCAL_OK = {
    "Sources/VibeDeckApp/IdeaView.swift", "Sources/VibeDeckApp/DocView.swift", "Sources/VibeDeckApp/WorkflowView.swift",  # modo de visualização
    "Sources/VibeDeckApp/ProjectWindow.swift",   # abas/seleção/expansão da janela
    "Sources/VibeDeckApp/VibeDeckApp.swift",     # projetos recentes (bookmarks)
    "Sources/VibeDeckApp/ClaudeSession.swift",   # modelo/esforço/provedor e chat atual
    "Sources/VibeDeckCore/ClaudeChats.swift",    # histórico de chats da máquina
    "Sources/VibeDeckCore/ClaudeUsage.swift",    # uso do Claude Code (statusline)
    "Sources/VibeDeckApp/ProjectTerminalView.swift",  # estado do terminal
    "Sources/VibeDeckApp/SkillIconCache.swift",  # cache de ícones baixados
    "Sources/VibeDeckApp/AIReadOnlyOperation.swift",  # modelo/esforço do provedor escolhidos no painel (preferência da máquina)
    "Sources/VibeDeckCore/AIPromptPolicy.swift",  # snapshots de contexto e uso de IA da máquina (Application Support), fora do repo
    "Sources/VibeDeckApp/RuleExecutionModel.swift",  # cache de duração dependente da máquina; regras/resultados continuam no repo
}
for f, s in allsrc.items():
    for i, l in enumerate(s.split("\n")):
        if re.search(r"UserDefaults|@AppStorage|@SceneStorage|applicationSupportDirectory|cachesDirectory|NSUbiquitousKeyValueStore", l) and f not in LOCAL_OK:
            fail(f"{f}:{i+1}: estado guardado fora do repo; dados do projeto vão em vibedeck.json/.vibedeck (preferência de UI/máquina: justifique e inclua no script): {l.strip()}")
sys.exit(bad)
PY
