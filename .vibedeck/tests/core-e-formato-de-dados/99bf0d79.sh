#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# VDJSON é a configuração canônica; JSONEncoder()/JSONDecoder() só em protocolos de fio (não arquivos do projeto).
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, os, re, sys
bad = 0
models = open("Sources/VibeDeckCore/Models.swift").read()
m = re.search(r'public enum VDJSON \{.*?\n\}', models, re.S)
vd = m.group(0) if m else ""
for needle, why in [(".prettyPrinted", "encoder prettyPrinted"), (".sortedKeys", "encoder sortedKeys"),
                    (".withoutEscapingSlashes", "encoder withoutEscapingSlashes"), ("dateEncodingStrategy = .iso8601", "datas ISO 8601 no encoder"),
                    ("strategy: .iso8601", "decoder aceita ISO 8601 sem frações"),
                    ("includingFractionalSeconds: true", "decoder aceita ISO 8601 com frações"),
                    ("append(0x0A)", "encode acrescenta \\n no fim")]:
    if needle not in vd:
        print(f"Sources/VibeDeckCore/Models.swift: VDJSON sem {why} ({needle})"); bad += 1
# Protocolos de fio / config externa: não gravam arquivos do projeto.
WIRE = {"Models.swift", "ReviewDiscover.swift", "Stack.swift", "CodexMCP.swift", "CodexRPC.swift", "ClaudeStream.swift"}
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    if os.path.basename(f) in WIRE: continue
    for n, l in enumerate(open(f).read().split("\n"), 1):
        if re.search(r'\bJSON(En|De)coder\(\)', l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: use VDJSON.encoder/decoder (ou VDJSON.encode) para arquivos do projeto: {l.strip()}"); bad += 1
sys.exit(1 if bad else 0)
PY
