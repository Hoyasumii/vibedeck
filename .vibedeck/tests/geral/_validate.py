"""Mini validador de JSON Schema (subset usado em schema/v1) + checagens extras do VibeDeck."""
import json, os, re, sys

UUID = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$')
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool,
         "integer": int, "number": (int, float), "null": type(None)}


def check_type(t, v):
    if t in ("integer", "number") and isinstance(v, bool):
        return False
    return isinstance(v, TYPES[t])


def validate(v, s, root, path, errs):
    if "$ref" in s:
        ref_file, _, ref_path = s["$ref"].partition("#")
        doc = json.load(open(f"schema/v1/{ref_file}")) if ref_file else root
        node = doc
        for part in [p for p in ref_path.split("/") if p]:
            node = node[part]
        return validate(v, node, doc, path, errs)
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(check_type(t, v) for t in ts):
            errs.append(f"{path}: tipo esperado {ts}, veio {type(v).__name__}")
            return
    if "enum" in s and v not in s["enum"]:
        errs.append(f"{path}: valor {v!r} fora do enum {s['enum']}")
    if "const" in s and v != s["const"]:
        errs.append(f"{path}: esperado {s['const']!r}, veio {v!r}")
    if isinstance(v, str):
        f = s.get("format")
        if f == "uuid" and not UUID.match(v):
            errs.append(f"{path}: {v!r} não é UUID")
        if f == "date-time" and not DATE.match(v):
            errs.append(f"{path}: {v!r} não é data ISO 8601")
        if "pattern" in s and not re.search(s["pattern"], v):
            errs.append(f"{path}: {v!r} não casa com /{s['pattern']}/")
        if len(v) < s.get("minLength", 0):
            errs.append(f"{path}: string curta demais")
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if "minimum" in s and v < s["minimum"]:
            errs.append(f"{path}: {v} < mínimo {s['minimum']}")
    if isinstance(v, dict):
        for r in s.get("required", []):
            if r not in v:
                errs.append(f"{path}: falta a chave obrigatória '{r}'")
        props = s.get("properties", {})
        for k, val in v.items():
            if k in props:
                validate(val, props[k], root, f"{path}.{k}", errs)
            elif s.get("additionalProperties") is False:
                errs.append(f"{path}: chave desconhecida '{k}'")
            elif isinstance(s.get("additionalProperties"), dict):
                validate(val, s["additionalProperties"], root, f"{path}.{k}", errs)
    if isinstance(v, list) and "items" in s:
        for i, it in enumerate(v):
            validate(it, s["items"], root, f"{path}[{i}]", errs)


def schema_for(rel):
    if rel == "vibedeck.json":
        return "project"
    m = re.match(r'^\.vibedeck/(reviews|rules|ideas|agents|commands|skills|workflows)/[^/]+\.json$', rel)
    if m:
        return {"reviews": "review-group", "rules": "rule-topic", "ideas": "idea", "agents": "agent",
                "commands": "command", "skills": "skill", "workflows": "workflow"}[m.group(1)]
    return None


def main(files):
    bad = 0
    kinds = None
    try:
        proj = json.load(open("vibedeck.json"))
        kinds = {k["id"] for k in proj.get("reviewKinds", [])} or None
    except Exception:
        pass
    for rel in files:
        name = schema_for(rel)
        if not name or not os.path.isfile(rel):
            continue
        try:
            data = json.load(open(rel))
        except Exception as e:
            print(f"{rel}: JSON inválido ({e})"); bad += 1; continue
        if not str(data.get("$schema", "")).endswith(f"/v1/{name}.schema.json"):
            print(f"{rel}: $schema ausente ou diferente de v1/{name}.schema.json"); bad += 1
        schema = json.load(open(f"schema/v1/{name}.schema.json"))
        errs = []
        validate(data, schema, schema, "$", errs)
        if name == "review-group" and kinds:
            for i, it in enumerate(data.get("items", [])):
                if it.get("kind") not in kinds:
                    errs.append(f"$.items[{i}].kind: '{it.get('kind')}' não está em reviewKinds")
        for e in errs:
            print(f"{rel}: {e}")
        bad += bool(errs)
    return bad


if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1:]) else 0)
