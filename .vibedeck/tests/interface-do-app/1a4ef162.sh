#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou no app, no Core Rust das ideias/tópicos ou no Package.swift.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -E "^Sources/VibeDeckApp/|^Package\.swift$|^crates/vibedeck-core/src/(ideas|app)\.rs$|^crates/vibedeck-core/src/rules/topics\.rs$|^crates/vibedeck-core/tests/ideas_core\.rs$" >/dev/null; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Tópico apagado por qualquer caminho despromove a ideia.
topics=crates/vibedeck-core/src/rules/topics.rs
ideas=crates/vibedeck-core/src/ideas.rs
appcore=crates/vibedeck-core/src/app.rs
pm=Sources/VibeDeckApp/ProjectModel.swift
# 1) Core: apagar o tópico (delete_record de regras) solta ideias e padrões órfãos.
python3 -I - "$topics" "$appcore" "$ideas" <<'PY' || fail=1
import re, sys
topics, appcore, ideas = (open(p).read() for p in sys.argv[1:4])
bad = 0
m = re.search(r"pub fn delete_topic\(.*?\n\}", topics, re.S)
if not m or "release_orphaned_ideas()" not in m.group(0):
    print(f"{sys.argv[1]}: delete_topic não chama release_orphaned_ideas"); bad = 1
m = re.search(r"RecordKind::Rules => \{.*?\n        \}", appcore, re.S)
if not m or "rules::delete_topic(store, slug)" not in m.group(0):
    print(f"{sys.argv[2]}: delete_record de regras não passa por rules::delete_topic"); bad = 1
if "pub fn release_orphaned_ideas(&self)" not in ideas:
    print(f"{sys.argv[3]}: release_orphaned_ideas ausente"); bad = 1
sys.exit(bad)
PY
# 2) App: 'Mover para o Lixo' usa o Core e recarrega ideias e projeto; mudança externa em regras recarrega as ideias.
python3 -I - "$pm" <<'PY' || fail=1
import re, sys
src = open(sys.argv[1]).read()
bad = 0
m = re.search(r"func deleteTopic\(.*?\n    \}", src, re.S)
if not m or "deleteRecord(.rule, slug: slug)" not in m.group(0) or "reloadIdeas()" not in m.group(0):
    print(f"{sys.argv[1]}: Mover para o Lixo (deleteTopic) não apaga pelo Core nem recarrega as ideias"); bad = 1
m = re.search(r"func handleExternalChanges\(.*?\n    \}", src, re.S)
if not m or not re.search(r"if topicsChanged \{[^}]*schedule\(\.ideas\)", m.group(0)):
    print(f"{sys.argv[1]}: handleExternalChanges não recarrega as ideias quando um tópico muda"); bad = 1
sys.exit(bad)
PY
# 3) Tópicos apagados fora do app (Finder, rm, outro processo) também soltam a ideia: alguém além de delete_topic
#    precisa chamar release_orphaned_ideas (hook de abertura/leitura do Core, ferramenta MCP ou chamada do app).
callers=$(grep -rn 'release_orphaned_ideas\|releaseOrphanedIdeas' crates Sources --include=*.rs --include=*.swift | grep -v '/tests/' | grep -v 'pub fn release_orphaned_ideas' | grep -v "^$topics" || true)
[ -n "$callers" ] || bad crates "nada solta ideias órfãs quando o tópico é apagado fora do app (só delete_topic chama release_orphaned_ideas)"
# 4) Teste do Core.
cargo test --offline -q -p vibedeck-core --test ideas_core orphaned_ideas_are_released_when_topic_disappears 2>&1 | grep -E "test result: ok\. [1-9]" >/dev/null || bad crates/vibedeck-core/tests/ideas_core.rs "teste orphaned_ideas_are_released_when_topic_disappears falhou"
iv=Sources/VibeDeckApp/IdeaView.swift
grep -q 'Button("Despromover", role: .destructive)' "$iv" || bad "$iv" "menu de contexto 'Despromover' ausente"
grep -q 'Promover para Regras' "$iv" || bad "$iv" "botão 'Promover para Regras' ausente"
grep -q 'Tópico: ' "$iv" || bad "$iv" "badge 'Tópico: …' ausente"
exit $fail
