#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Toda chave de CodingKeys dos modelos persistidos existe no schema/v1 correspondente.
applies '(^|/)(Sources/VibeDeckCore/(Models|Rules|AgentsGuide)\.swift|schema/v1/)'
python3 -I - <<'PY'
import json, re, sys
bad = 0
MAP = {  # arquivo Swift -> {struct: schema}
    "Sources/VibeDeckCore/Models.swift": {"Project": "project", "Link": "project", "ReviewKind": "project", "ReviewTarget": "review-group",
                                           "ReviewItem": "review-group", "ReviewGroup": "review-group"},
    "Sources/VibeDeckCore/Rules.swift": {"Rule": "rule-topic", "RuleTest": "rule-topic", "RuleTopic": "rule-topic", "Idea": "idea",
                                         "RuleResult": "rule-check", "RuleCheck": "rule-check"},
}
def prop_names(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "properties" and isinstance(v, dict): out.update(v.keys())
            prop_names(v, out)
    elif isinstance(node, list):
        for v in node: prop_names(v, out)
    return out
for f, structs in MAP.items():
    src = open(f).read()
    for struct, schema in structs.items():
        m = re.search(r'^public struct %s\b.*?\n\}' % struct, src, re.S | re.M)
        if not m:
            print(f"{f}: struct {struct} não encontrada"); bad += 1; continue
        ck = re.search(r'enum CodingKeys[^{]*\{([^}]*)\}', m.group(0))
        if not ck: continue
        body = ck.group(1)
        keys = set()
        for line in body.split("\n"):
            line = re.sub(r'//.*', '', line)
            for part in re.sub(r'^\s*case\s+', '', line).split(","):
                name, _, raw = part.partition("=")
                name = name.strip(); raw = raw.strip().strip('"')
                if re.fullmatch(r'\w+', name) and name != "case": keys.add(raw or name)
        path = f"schema/v1/{schema}.schema.json"
        props = prop_names(json.load(open(path)), set())
        for k in sorted(keys - props):
            print(f"{f}: {struct}.{k} não está em {path} (atualize o schema e, se preciso, AgentsGuide.swift)"); bad += 1
sys.exit(1 if bad else 0)
PY
