#!/usr/bin/env python3
"""Offline CLI/MCP acceptance contract, exercised in a disposable project."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="reorganize-contract-") as temporary:
    root = Path(temporary)

    def cli(*args, success=True):
        result = subprocess.run([binary, *args], cwd=root, capture_output=True, text=True, timeout=30)
        assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
        return result.stdout

    def snapshot():
        return {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}

    cli("init")
    cli("docs", "new", "Documento", "--body", "Original")
    original = snapshot()
    context = json.loads(cli("reorganize", "prompt"))
    assert snapshot() == original
    answer = {"actions": [{"id": "move-doc", "kind": "move", "item": {"concept": "docs", "slug": "documento"},
                            "involved": [], "reason": "Agrupar documento", "destination": "grupo"}]}
    answer_file = root / "answer.json"
    answer_file.write_text(json.dumps(answer))
    proposed = json.loads(cli("reorganize", "validate", "--file", str(answer_file), "--fingerprint", context["fingerprint"]))
    assert proposed["actions"][0]["item"]["concept"] == "docs"
    proposal_file = root / "proposal.json"
    proposal_file.write_text(json.dumps(proposed))
    accept_file = root / "acceptance.json"
    accept_file.write_text(json.dumps({"selected": [], "conflicts": {}}))
    cli("reorganize", "apply", "--file", str(proposal_file), "--acceptance", str(accept_file))
    assert (root / ".vibedeck/docs/documento.md").exists()
    accept_file.write_text(json.dumps({"selected": ["move-doc"], "conflicts": {}}))
    cli("reorganize", "apply", "--file", str(proposal_file), "--acceptance", str(accept_file))
    assert (root / ".vibedeck/docs/grupo/documento.md").read_bytes() == original[".vibedeck/docs/documento.md"]
    cli("reorganize", "apply", "--file", str(proposal_file), "--acceptance", str(accept_file), success=False)

    process = subprocess.Popen([binary, "mcp"], cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
    counter = 0

    def rpc(method, params):
        global counter
        counter += 1
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": counter, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        while True:
            line = process.stdout.readline()
            assert line, "MCP encerrou sem resposta"
            reply = json.loads(line)
            if reply.get("id") == counter:
                assert "error" not in reply, reply
                return reply["result"]

    def tool(name, **arguments):
        return rpc("tools/call", {"name": name, "arguments": arguments})

    try:
        rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "reorganize-test", "version": "1"}})
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        process.stdin.flush()
        definitions = rpc("tools/list", {})["tools"]
        assert {"reorganize_prompt", "reorganize_analyze", "reorganize_validate", "reorganize_apply"}.issubset({t["name"] for t in definitions})
        before = snapshot()
        prompt = json.loads(tool("reorganize_prompt")["content"][0]["text"])
        assert before == snapshot()
        flow = {"actions": [{"id": "flow", "kind": "flow", "item": {"concept": "docs", "slug": "grupo/documento"},
                             "involved": [], "reason": "Melhorar o fluxo do documento", "title": "Melhoria", "content": "Proposta de melhoria"}]}
        validated = tool("reorganize_validate", answer=json.dumps(flow), fingerprint=prompt["fingerprint"])
        assert not validated.get("isError"), validated
        assert before == snapshot()
        applied = tool("reorganize_apply", proposal=validated["content"][0]["text"], acceptance=json.dumps({"selected": ["flow"], "conflicts": {}}))
        assert not applied.get("isError"), applied
        idea = json.loads((root / ".vibedeck/ideas/melhoria.json").read_text())
        assert idea["author"] == "ai" and not idea.get("promotedTopic")
        assert tool("reorganize_validate", answer="invalid", fingerprint=prompt["fingerprint"]).get("isError")
    finally:
        process.stdin.close()
        process.wait(timeout=10)
print("CLI/MCP: proposta somente leitura, aceite explícito, rejeição de proposta antiga e autoria IA aprovados.")
