#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Todo campo serializado dos modelos persistidos existe no schema/v1 correspondente e o guia (guide_reference.md) cita os schemas.
applies '(^|/)(crates/vibedeck-core/src/(model/|ai/guide)|schema/v1/)'
python3 -I - <<'PY'
import json, re, sys
bad = 0
MAP = {  # arquivo Rust -> {struct: schema}
    "model/project.rs": {"Project": "project", "Link": "project", "ReviewKind": "project", "StackItem": "project", "ProjectPattern": "project"},
    "model/review_group.rs": {"ReviewTarget": "review-group", "ReviewItem": "review-group", "ReviewGroup": "review-group"},
    "model/rule_topic.rs": {"Rule": "rule-topic", "RuleTest": "rule-topic", "RuleTopic": "rule-topic"},
    "model/idea.rs": {"Idea": "idea", "IdeaReadiness": "idea"},
    "model/rule_check.rs": {"RuleResult": "rule-check", "RuleCheck": "rule-check"},
    "model/workflow.rs": {"Workflow": "workflow", "WorkflowStep": "workflow", "WorkflowTransition": "workflow"},
    "model/workflow_run.rs": {"WorkflowRun": "workflow-run", "WorkflowRunEntry": "workflow-run", "WorkflowQuestion": "workflow-run",
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
base = "crates/vibedeck-core/src/"
for f, structs in MAP.items():
    src = open(base + f).read()
    src = src[:src.find("#[cfg(test)]")] if "#[cfg(test)]" in src else src
    for struct, schema in structs.items():
        keys = fields(src, struct)
        if not keys:
            print(f"{base}{f}: struct {struct} não encontrada"); bad += 1; continue
        path = f"schema/v1/{schema}.schema.json"
        props = prop_names(json.load(open(path)), set())
        for k in sorted(keys - props):
            print(f"{base}{f}: {struct}.{k} não está em {path} (atualize o schema e, se preciso, ai/guide_reference.md)"); bad += 1
ref = open(base + "ai/guide_reference.md").read()
m = re.search(r'Schemas:\s*\S*/\{([^}]*)\}\.schema\.json', ref)
listed = {x.strip() for x in m.group(1).split(",")} if m else set()
for s in {v for d in MAP.values() for v in d.values()}:
    if s not in listed:
        print(f"{base}ai/guide_reference.md: schema {s} não está na linha \"Schemas:\""); bad += 1
sys.exit(1 if bad else 0)
PY
