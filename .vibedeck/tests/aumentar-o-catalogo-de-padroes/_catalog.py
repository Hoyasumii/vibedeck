"""Lê o catálogo embutido (PatternCatalog::all, assets/patterns/catalog.json) sem compilar. Uso: import _catalog; _catalog.load()."""
import re

def parse(text):
    import json
    out = []
    for t in json.loads(text):
        out.append({'id': t['id'], 'name': t['name'], 'category': t['category'], 'summary': t['summary'],
                    'aliases': t.get('aliases', []),
                    'rules': [{'text': r['text'], 'details': r.get('details'), 'severity': r.get('severity', 'must')} for r in t['rules']]})
    return out

def load(path='crates/vibedeck-core/assets/patterns/catalog.json'):
    return parse(open(path, encoding='utf-8').read())

import unicodedata

def slug(text):
    folded = ''.join(c for c in unicodedata.normalize('NFKD', text) if not unicodedata.combining(c)).lower().replace('ß', 'ss')
    out = re.sub(r'[^a-z0-9]+', '-', folded).strip('-')
    return out[:60].rstrip('-') if out else 'untitled'

def refs(t):
    return [t['id'], t['name']] + t['aliases']

def matches(t, ref):
    k = slug(ref)
    return bool(ref.strip()) and any(slug(r) == k for r in refs(t))

def original_catalog():
    # Snapshot imutável do catálogo antes da expansão de oito templates.
    import json
    from pathlib import Path
    templates = json.loads(Path(__file__).with_name('catalog-before-expansion.json').read_text(encoding='utf-8'))['templates']
    # O snapshot veio do parser antigo, que gravou a ausência de details como a string 'nil'.
    for t in templates:
        for r in t['rules']:
            if r.get('details') == 'nil': r['details'] = None
    return templates

def mcp_calls(calls, binary='target/debug/vibedeck', timeout=90):
    """Abre `vibedeck mcp` (stdio), faz handshake e chama cada (tool, args) em sequência; devolve a lista de textos de resultado."""
    import json, subprocess, threading
    p = subprocess.Popen([binary, 'mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    timer = threading.Timer(timeout, p.kill); timer.start()
    def send(m): p.stdin.write(json.dumps(m) + '\n'); p.stdin.flush()
    def recv(): return json.loads(p.stdout.readline())
    try:
        send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'vd-test', 'version': '1'}}}); recv()
        send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        out = []
        for n, (tool, args) in enumerate(calls):
            send({'jsonrpc': '2.0', 'id': 2 + n, 'method': 'tools/call', 'params': {'name': tool, 'arguments': args}})
            out.append(recv()['result']['content'][0]['text'])
        return out
    finally:
        timer.cancel(); p.kill()
