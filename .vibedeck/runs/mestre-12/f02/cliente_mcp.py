"""Cliente MCP mínimo (stdio): handshake, tools/list, leitura e escrita, cancelamento, EOF."""
import json, subprocess, sys
cmd = sys.argv[1:]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
msgs = [
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"prova","version":"1"}}},
 {"jsonrpc":"2.0","method":"notifications/initialized"},
 {"jsonrpc":"2.0","id":2,"method":"tools/list"},
 {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_ideas","arguments":{}}},
 {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"add_idea","arguments":{"title":"Prova SSH F02","description":"criada pela prova"}}},
 {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":99}},
 {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_idea","arguments":{"idea":"prova-ssh-f02"}}},
 {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nao_existe","arguments":{}}},
]
out, err = p.communicate("\n".join(json.dumps(m) for m in msgs) + "\n", timeout=60)
replies = [json.loads(l) for l in out.splitlines() if l.strip()]
by = {r["id"]: r for r in replies}
assert len(replies) == 6, replies
init = by[1]["result"]
print("protocolVersion", init["protocolVersion"], "server", init["serverInfo"])
print("tools", len(by[2]["result"]["tools"]))
lst = by[3]["result"]; print("list_ideas isError", lst.get("isError", False), "chars", len(lst["content"][0]["text"]))
print("add_idea", by[4]["result"].get("isError", False), by[4]["result"]["content"][0]["text"][:80].replace("\n"," "))
print("get_idea", by[5]["result"].get("isError", False))
print("desconhecida isError", by[6]["result"]["isError"])
print("exit", p.returncode, "stderr bytes", len(err))
assert p.returncode == 0 and not by[5]["result"].get("isError") and by[6]["result"]["isError"]
print("OK")
