#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
build_cli
py <<'PY' || fail=1
import _catalog as c, json, os, sys
ids = os.environ["NEW_IDS"].split()
res = c.mcp_calls([("pattern_catalog", {})] + [("pattern_catalog", {"query": i}) for i in ids])
got = [{t["id"] for t in json.loads(r)} for r in res]
bad = [f"pattern_catalog sem query não inclui {i}" for i in ids if i not in got[0]]
bad += [f"pattern_catalog query={i} não inclui {i}" for n, i in enumerate(ids) if i not in got[1 + n]]
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
