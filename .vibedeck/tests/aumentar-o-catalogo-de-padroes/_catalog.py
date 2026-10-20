"""Extrai o catálogo (PatternCatalog.all) de um Patterns.swift sem compilar. Uso: import _catalog; _catalog.parse(texto)."""
import re

def _string(s, i):
    assert s[i] == '"', s[i:i+30]
    i += 1; out = []
    while s[i] != '"':
        if s[i] == '\\':
            c = s[i+1]
            out.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\'}.get(c, c)); i += 2
        else:
            out.append(s[i]); i += 1
    return ''.join(out), i + 1

def _ws(s, i):
    while True:
        while s[i].isspace(): i += 1
        if s.startswith('//', i):
            while s[i] != '\n': i += 1
        else:
            return i

def _value(s, i):
    i = _ws(s, i)
    if s[i] == '"': return _string(s, i)
    if s[i] == '[':
        items = []; i = _ws(s, i + 1)
        while s[i] != ']':
            v, i = _value(s, i); items.append(v); i = _ws(s, i)
            if s[i] == ',': i = _ws(s, i + 1)
        return items, i + 1
    m = re.compile(r'\.?[A-Za-z_]\w*').match(s, i)
    if m and s[m.end()] == '(':
        name = m.group(0); i = _ws(s, m.end() + 1); args = []; kw = {}
        while s[i] != ')':
            km = re.compile(r'([A-Za-z_]\w*)\s*:').match(s, i)
            key = None
            if km: key = km.group(1); i = km.end()
            v, i = _value(s, i); i = _ws(s, i)
            (kw.__setitem__(key, v) if key else args.append(v))
            if s[i] == ',': i = _ws(s, i + 1)
        return (name, args, kw), i + 1
    if m: return m.group(0), m.end()
    raise ValueError(s[i:i+40])

def parse(text):
    start = text.index('public static let all: [PatternTemplate] = [')
    i = _ws(text, text.index('[', text.index('=', start)) + 1)
    out = []
    while text[i] != ']':
        (name, args, kw), i = _value(text, i)
        assert name == 'PatternTemplate', name
        rules = []
        for _, rargs, rkw in kw['rules']:
            rules.append({'text': rargs[0], 'details': rargs[1] if len(rargs) > 1 else None,
                          'severity': (rkw.get('severity') or '.must').lstrip('.')})
        out.append({'id': kw['id'], 'name': kw['name'], 'category': kw['category'], 'summary': kw['summary'],
                    'aliases': kw.get('aliases', []), 'rules': rules})
        i = _ws(text, i)
        if text[i] == ',': i = _ws(text, i + 1)
    return out

def load(path='Sources/VibeDeckCore/Patterns.swift'):
    return parse(open(path, encoding='utf-8').read())

import unicodedata

def slug(text):
    folded = ''.join(c for c in unicodedata.normalize('NFKD', text.lower()) if not unicodedata.combining(c))
    out = re.sub(r'[^a-z0-9]+', '-', folded).strip('-')
    return out[:60].rstrip('-') if out else 'untitled'

def refs(t):
    return [t['id'], t['name']] + t['aliases']

def matches(t, ref):
    k = slug(ref)
    return bool(ref.strip()) and any(slug(r) == k for r in refs(t))

def head_catalog():
    import subprocess
    return parse(subprocess.check_output(['git', 'show', 'HEAD:Sources/VibeDeckCore/Patterns.swift'], text=True))

def mcp_calls(calls, binary='.build/debug/vibedeck', timeout=90):
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
