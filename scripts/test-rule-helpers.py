#!/usr/bin/env python3
"""Verify that rule helpers link tests and reject build errors or empty filters."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
helpers = sorted(p for p in (root / '.vibedeck/tests').glob('*/_lib.sh')
                 if 'swift test --skip-build' in p.read_text())
assert helpers, 'No test helpers found'
with tempfile.TemporaryDirectory(prefix='vibedeck-rule-helpers-') as directory:
    fixture = Path(directory)
    tests = fixture / 'Tests/VibeDeckCoreTests'
    tests.mkdir(parents=True)
    (tests / 'Fixture.swift').write_text('func selected() {}\n')
    binary = fixture / 'swift'
    binary.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$CALLS"
if [ "$1" = build ]; then
  [ "$*" = 'build --build-tests' ] || exit 9
  [ "$MODE" != build-fail ] || { echo 'compilation failed'; exit 1; }
elif [ "$1" = test ]; then
  [ "$MODE" != test-fail ] || { echo 'test failed'; exit 1; }
  if [ "$MODE" = empty ]; then echo 'Test run with 0 tests passed';
  else echo 'Test run with 1 test passed'; fi
else exit 10; fi
''')
    binary.chmod(0o755)
    for helper in helpers:
        for mode in ['pass', 'build-fail', 'test-fail', 'empty']:
            calls = fixture / 'calls'
            calls.write_text('')
            env = dict(os.environ, PATH=f'{fixture}:{os.environ["PATH"]}',
                       VIBEDECK_ROOT=str(fixture), MODE=mode, CALLS=str(calls))
            result = subprocess.run(['bash', '-c',
                'source "$1"; TESTS=Tests/VibeDeckCoreTests/Fixture.swift; run_tests Fixture/selected',
                'helper-check', str(helper)], env=env, capture_output=True, text=True, timeout=10)
            assert (result.returncode == 0) == (mode == 'pass'), (helper, mode, result.stdout, result.stderr)
            invocations = calls.read_text().splitlines()
            assert invocations[0] == 'build --build-tests', (helper, invocations)
            if mode == 'build-fail':
                assert not any(line.startswith('test ') for line in invocations), (helper, invocations)
            if mode == 'empty':
                assert 'nenhum teste rodou' in result.stdout, (helper, result.stdout)
print(f'{len(helpers)} helpers: linked build, build failure, test failure and empty filter verified')
