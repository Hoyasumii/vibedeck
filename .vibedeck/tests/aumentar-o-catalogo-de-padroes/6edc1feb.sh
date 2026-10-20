#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
build_cli
tmp=$(mktemp -d)
.build/debug/vibedeck patterns catalog --json > "$tmp/all.json"
for i in $NEW_IDS; do .build/debug/vibedeck patterns catalog "$i" --json > "$tmp/$i.json"; done
VD_TMP="$tmp" py <<'PY' || fail=1
import json, os
d = os.environ["VD_TMP"]; ids = os.environ["NEW_IDS"].split(); bad = []
all_ = {t["id"] for t in json.load(open(f"{d}/all.json"))}
for i in ids:
    if i not in all_: bad.append(f"patterns catalog --json sem {i}")
    if i not in {t["id"] for t in json.load(open(f"{d}/{i}.json"))}: bad.append(f"patterns catalog {i} --json não encontra {i}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
rm -rf "$tmp"
finish
