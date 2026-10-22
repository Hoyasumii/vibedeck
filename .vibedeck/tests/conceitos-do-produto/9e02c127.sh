#!/usr/bin/env bash
# Dados do projeto vivem em vibedeck.json + .vibedeck/: sem banco nem estado oculto; todo campo persistido do Core Rust
# está no schema e todo diretório/schema está descrito no guia (ai/guide_reference.md → AGENTS.md/guide.md).
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^(Sources|crates)/|^schema/|^Cargo\.toml$" >/dev/null; then exit 77; fi
python3 -I - <<'PY'
import re, glob, json, sys
bad = 0
def fail(msg):
    global bad; print(msg); bad = 1
def strip_tests(s): return s[:s.find("#[cfg(test)]")] if "#[cfg(test)]" in s else s
M = "crates/vibedeck-core/src/"
# 1. Todo campo serializado (camelCase) dos modelos persistidos está em `properties` do schema/v1 do arquivo que o guarda.
MAP = {
    "project.rs": {"Project": "project", "Link": "project", "ReviewKind": "project", "StackItem": "project", "ProjectPattern": "project"},
    "review_group.rs": {"ReviewTarget": "review-group", "ReviewItem": "review-group", "ReviewGroup": "review-group"},
    "rule_topic.rs": {"Rule": "rule-topic", "RuleTest": "rule-topic", "RuleTopic": "rule-topic"},
    "idea.rs": {"Idea": "idea", "IdeaReadiness": "idea"},
    "rule_check.rs": {"RuleResult": "rule-check", "RuleCheck": "rule-check"},
    "workflow.rs": {"Workflow": "workflow", "WorkflowStep": "workflow", "WorkflowTransition": "workflow"},
    "workflow_run.rs": {"WorkflowRun": "workflow-run", "WorkflowRunEntry": "workflow-run", "WorkflowQuestion": "workflow-run",
                        "WorkflowQuestionOption": "workflow-run", "WorkflowStepCheckpoint": "workflow-run"},
}
def prop_names(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "properties" and isinstance(v, dict): out.update(v.keys())
            prop_names(v, out)
    elif isinstance(node, list):
        for v in node: prop_names(v, out)
    return out
def camel(s):
    p = s.split("_"); return p[0] + "".join(x.capitalize() for x in p[1:])
def fields(src, name):
    keys = set()
    for sn in (name, name + "Wire"):
        m = re.search(r'\bstruct %s\s*\{' % sn, src)
        if not m: continue
        i, depth = m.end(), 1
        while depth and i < len(src):
            depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
        pend = ""
        for line in src[m.end():i - 1].split("\n"):
            t = line.strip()
            if t.startswith("#["): pend += t; continue
            fm = re.match(r'(?:pub )?(\w+):', t)
            if fm:
                r = re.search(r'rename = "([^"]+)"', pend)
                keys.add(r.group(1) if r else camel(fm.group(1)))
            if t and not t.startswith("//"): pend = ""
    return keys
schemas = {}
def schema(name):
    if name not in schemas:
        p = f"schema/v1/{name}.schema.json"
        try: schemas[name] = prop_names(json.load(open(p)), set())
        except FileNotFoundError: fail(f"{p}: não existe"); schemas[name] = set()
        except ValueError as e: fail(f"{p}: JSON inválido ({e})"); schemas[name] = set()
    return schemas[name]
for f, structs in MAP.items():
    src = strip_tests(open(M + "model/" + f).read())
    for st, sname in structs.items():
        keys = fields(src, st)
        if not keys: fail(f"{M}model/{f}: struct {st} não encontrada"); continue
        for k in sorted(keys - schema(sname)):
            fail(f"schema/v1/{sname}.schema.json: campo \"{k}\" de {st} ({M}model/{f}) não está descrito no schema")
# 2. O guia (guide_reference.md) descreve cada diretório de .vibedeck/ e lista cada schema.
guide = open(M + "ai/guide_reference.md").read()
store = open(M + "store.rs").read()
m = re.search(r'pub fn ensure_directories.*?for d in \[(.*?)\]', store, re.S)
dirs = re.findall(r'"([\w-]+)"', m.group(1)) if m else []
if not dirs: fail(f"{M}store.rs: lista de diretórios de ensure_directories não encontrada")
for d in dirs + ["runs"]:
    if not re.search(r"^\s+%s/" % re.escape(d), guide, re.M):
        fail(f"{M}ai/guide_reference.md: diretório .vibedeck/{d}/ não está descrito no guia")
lst = re.search(r"Schemas: \{SCHEMA_BASE\}/\{([^}]*)\}\.schema\.json", guide)
listed = set(x.strip() for x in lst.group(1).split(",")) if lst else set()
for sname in {v for d in MAP.values() for v in d.values()} | {"agent", "command", "skill"}:
    if sname not in listed: fail(f"{M}ai/guide_reference.md: schema {sname} não está listado no guia")
if "vibedeck.json" not in guide: fail(f"{M}ai/guide_reference.md: o guia não descreve o vibedeck.json")
# 3. Sem banco de dados nem persistência oculta de dados do projeto.
for cf in glob.glob("Cargo.toml") + glob.glob("crates/*/Cargo.toml"):
    for i, l in enumerate(open(cf).read().split("\n")):
        if re.match(r"\s*(rusqlite|sqlx|diesel|sea-orm|sled|redb|rocksdb|heed|lmdb\w*|sqlite\w*)\s*=", l):
            fail(f"{cf}:{i+1}: banco de dados ({l.strip()}): dados do projeto devem ficar em arquivos do repo")
swift = sorted(glob.glob("Sources/**/*.swift", recursive=True))
for f in swift:
    for i, l in enumerate(open(f).read().split("\n")):
        if re.match(r"\s*import (SQLite3?|CoreData|SwiftData|GRDB|RealmSwift|Realm)\b", l):
            fail(f"{f}:{i+1}: banco de dados ({l.strip()}): dados do projeto devem ficar em arquivos do repo")
# Estado fora do repo só para preferências de UI e dados da máquina (chats/uso de IA, logs, terminal, cache de ícones).
APP = "Sources/VibeDeckApp/"
LOCAL_OK = {APP + p for p in (
    "IdeaView.swift", "DocView.swift", "WorkflowView.swift",       # modo de visualização
    "V2/V2ProjectWindow.swift",                                    # abas/seleção/expansão da janela
    "VibeDeckApp.swift",                                           # projetos recentes (bookmarks)
    "ClaudeSession.swift",                                         # modelo/esforço/provedor e chat atual
    "Core/AI/ClaudeChats.swift",                                   # histórico de chats da máquina
    "Core/AI/ClaudeUsage.swift",                                   # uso do Claude Code (statusline)
    "ProjectTerminalView.swift",                                   # estado do terminal
    "SkillIconCache.swift",                                        # cache de ícones baixados
    "AIReadOnlyOperation.swift",                                   # modelo/esforço do provedor escolhidos no painel (preferência da máquina)
    "Core/AI/AIPromptPolicy.swift",                                # snapshots de contexto e uso de IA da máquina, fora do repo
    "RuleExecutionModel.swift",                                    # cache de duração dependente da máquina; regras/resultados continuam no repo
    "AppSettingsView.swift",                                       # limite de scripts simultâneos: depende dos núcleos da máquina
    "Core/Support/Logging.swift",                                  # logs de erros/crashes da máquina, fora do repo e do git
)}
for f in swift:
    for i, l in enumerate(open(f).read().split("\n")):
        if re.search(r"UserDefaults|@AppStorage|@SceneStorage|applicationSupportDirectory|cachesDirectory|NSUbiquitousKeyValueStore", l) and f not in LOCAL_OK:
            fail(f"{f}:{i+1}: estado guardado fora do repo; dados do projeto vão em vibedeck.json/.vibedeck (preferência de UI/máquina: justifique e inclua no script): {l.strip()}")
# Rust: diretório da máquina (HOME/XDG/Application Support) só para dados da máquina: uso/contexto de IA, instalação de MCP, logs, importação de itens.
RUST_LOCAL_OK = {M + p for p in ("ai/mod.rs", "ai/provider.rs", "ai/mcp_install.rs", "ai/usage.rs", "ai/context.rs", "project/logs.rs", "resources/import.rs")}
RUST_LOCAL_OK |= {"crates/vibedeck/src/cli/mod.rs", "crates/vibedeck/src/cli/project.rs"}   # só expandem `~` em caminhos passados pelo usuário
for f in sorted(glob.glob("crates/**/*.rs", recursive=True)):
    if "/tests/" in f or f in RUST_LOCAL_OK: continue
    for i, l in enumerate(strip_tests(open(f).read()).split("\n")):
        if l.strip().startswith("//"): continue
        if re.search(r'\bhome_dir\(|\bmachine_dir\(|\blocal_store_dir\(|XDG_\w+|var_os\("HOME"\)|Application Support', l):
            fail(f"{f}:{i+1}: estado fora do repo; dados do projeto vão em vibedeck.json/.vibedeck (dado da máquina: justifique e inclua no script): {l.strip()}")
sys.exit(bad)
PY
