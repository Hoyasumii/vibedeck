#!/usr/bin/env python3
"""Exercise grouped CLI/MCP records and destructive-operation safeguards in a disposable project.
Usage: python3 scripts/test-item-groups.py /path/to/vibedeck
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='vibedeck-groups-contract-') as temporary:
    root = Path(temporary)

    def cli(*args, success=True):
        result = subprocess.run([binary, *args], cwd=root, capture_output=True, text=True, timeout=30)
        assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
        return result.stdout

    cli('init')
    cli('ideas', 'new', 'Ideia', '--reference', 'a/b/x', '--ai')
    cli('docs', 'new', 'Doc', '--reference', 'a/b/x', '--ai')
    cli('skills', 'new', 'Skill', '--reference', 'a/b/x', '--ai')
    cli('review', 'add', 'a/b/tema', 'Nota', '--kind', 'note', '--ai')
    for command in [('ideas', 'list'), ('docs', 'list'), ('skills', 'list'), ('review', 'groups')]:
        rows = json.loads(cli(*command, '--json'))
        assert rows[0]['group'] == 'a/b', (command, rows)
    idea_bytes = (root / '.vibedeck/ideas/a/b/x.json').read_bytes()
    cli('groups', 'remove', 'ideas', 'a', success=False)
    assert (root / '.vibedeck/ideas/a/b/x.json').read_bytes() == idea_bytes
    cli('groups', 'move', 'ideas', 'a', 'a/b', success=False)
    cli('groups', 'rename', 'ideas', 'a', 'c')
    assert (root / '.vibedeck/ideas/c/b/x.json').read_bytes() == idea_bytes

    process = subprocess.Popen([binary, 'mcp'], cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    counter = 0

    def rpc(method, params):
        global counter
        counter += 1
        process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': counter, 'method': method, 'params': params}) + '\n')
        process.stdin.flush()
        while True:
            line = process.stdout.readline()
            assert line, 'MCP encerrou sem resposta'
            reply = json.loads(line)
            if reply.get('id') == counter:
                assert 'error' not in reply, reply
                return reply['result']

    def tool(name, **args):
        return rpc('tools/call', {'name': name, 'arguments': args})

    try:
        rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'group-tests', 'version': '1'}})
        process.stdin.write(json.dumps({'jsonrpc': '2.0', 'method': 'notifications/initialized'}) + '\n')
        process.stdin.flush()
        for name, group in [('list_ideas', 'c/b'), ('list_docs', 'a/b'), ('list_skills', 'a/b'), ('list_review_groups', 'a/b')]:
            result = tool(name)
            rows = json.loads(result['content'][0]['text'])
            assert rows[0]['group'] == group, (name, rows)
        result = tool('item_groups', action='delete', concept='ideas', path='c')
        assert result.get('isError'), result
        assert (root / '.vibedeck/ideas/c/b/x.json').read_bytes() == idea_bytes
        assert not tool('item_groups', action='create', concept='ideas', path='vazio/sub').get('isError')
        result = tool('item_groups', action='list', concept='ideas')
        assert {'path': 'vazio/sub'} in json.loads(result['content'][0]['text'])
        assert not tool('item_groups', action='move', concept='ideas', **{'from': 'c', 'to': 'd'}).get('isError')
        assert not tool('item_groups', action='delete', concept='ideas', path='d', confirmed=True).get('isError')
        assert not (root / '.vibedeck/ideas/d').exists()
    finally:
        process.stdin.close()
        process.wait(timeout=10)
print('CLI/MCP: agrupamento, JSON, movimentos e confirmação aprovados.')
