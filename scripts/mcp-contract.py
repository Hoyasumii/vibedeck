#!/usr/bin/env python3
"""Measures the MCP context budget and extracts the tool contract (no descriptions).

usage: mcp-contract.py <vibedeck-binary> snapshot <fixtures-dir>   # writes the baseline
       mcp-contract.py <vibedeck-binary> check <fixtures-dir>      # compares with it
Offline: talks JSON-RPC to `vibedeck mcp` over stdio, never calls an AI provider.
"""
import json
import os
import subprocess
import sys

POLICY_MARKER = "Trabalhe por escopo"
REQUIRED_IN_INSTRUCTIONS = ["rules_for", "submit_rule_check", "passed=true", "verify_manual", "AGENTS.md"]
SAMPLE_FILES = ["Sources/VibeDeckCore/Rules.swift"]


def call(binary):
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "budget", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
         "params": {"name": "rules_for", "arguments": {"files": SAMPLE_FILES}}},
    ]
    # The server stops at EOF, so stdin stays open until every reply has arrived.
    proc = subprocess.Popen([binary, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    for m in messages:
        proc.stdin.write(json.dumps(m) + "\n")
    proc.stdin.flush()
    replies = {}
    while len(replies) < 3:
        line = proc.stdout.readline()
        if not line:
            sys.exit("vibedeck mcp encerrou antes de responder")
        if line.strip():
            message = json.loads(line)
            if "id" in message:
                replies[message["id"]] = message
    proc.stdin.close()
    proc.wait(timeout=30)
    return replies[1]["result"].get("instructions", ""), replies[2]["result"]["tools"], replies[3]["result"]


def contract(tools):
    def shape(schema):
        props = schema.get("properties", {})
        return {
            "properties": {k: {"type": v.get("type"), "enum": v.get("enum"), "items": shape(v["items"]) if isinstance(v.get("items"), dict) and "properties" in v["items"] else v.get("items")} for k, v in sorted(props.items())},
            "required": sorted(schema.get("required", [])),
        }
    return {t["name"]: shape(t.get("inputSchema", {})) for t in sorted(tools, key=lambda t: t["name"])}


def sizes(instructions, tools, rules_for):
    return {
        "instructions": len(instructions),
        "tools": len(json.dumps(tools, ensure_ascii=False)),
        "rules_for": len(json.dumps(rules_for, ensure_ascii=False)),
    }


def main():
    binary, mode, fixtures = sys.argv[1:4]
    instructions, tools, rules_for = call(binary)
    current_contract, current = contract(tools), sizes(instructions, tools, rules_for)
    contract_path = os.path.join(fixtures, "mcp-contract.json")
    baseline_path = os.path.join(fixtures, "mcp-budget-baseline.json")
    if mode == "snapshot":
        os.makedirs(fixtures, exist_ok=True)
        json.dump(current_contract, open(contract_path, "w"), indent=1, sort_keys=True)
        json.dump(current, open(baseline_path, "w"), indent=1, sort_keys=True)
        print(json.dumps(current))
        return
    errors = []
    # Backward compatible only: every tool, parameter, type, enum and `required` list stays; new optional
    # parameters may be added.
    for name, old in json.load(open(contract_path)).items():
        new = current_contract.get(name)
        if new is None:
            errors.append(f"tool removida: {name}")
            continue
        if new["required"] != old["required"]:
            errors.append(f"{name}: required mudou {old['required']} -> {new['required']}")
        for prop, shape in old["properties"].items():
            if new["properties"].get(prop) != shape:
                errors.append(f"{name}.{prop}: {shape} -> {new['properties'].get(prop)}")
    baseline = json.load(open(baseline_path))
    if current["tools"] > baseline["tools"] * 0.70:
        errors.append(f"catálogo de tools {current['tools']} > 70% da baseline {baseline['tools']}")
    if current["instructions"] > 1200:
        errors.append(f"instruções do MCP com {current['instructions']} caracteres (> 1200)")
    if POLICY_MARKER in instructions:
        errors.append("instruções do MCP repetem AIPromptPolicy (já está no AGENTS.md)")
    errors += [f"instruções do MCP sem '{w}'" for w in REQUIRED_IN_INSTRUCTIONS if w not in instructions]
    for k in current:
        print(f"{k}: {baseline[k]} -> {current[k]} ({100 - 100 * current[k] // max(baseline[k], 1)}% menor)")
    if errors:
        print("\n".join(errors))
        sys.exit(1)


if __name__ == "__main__":
    main()
