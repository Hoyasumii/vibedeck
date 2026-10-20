"""A regra de autoria aceita movimentos e bloqueia perda ou reatribuição de itens humanos."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

rule = Path(__file__).resolve().parents[1] / '.vibedeck/tests/geral/ac4ba963.sh'
with tempfile.TemporaryDirectory(prefix='vibedeck-human-moves-') as directory:
    root = Path(directory)

    def git(*args):
        subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)

    def write(path, author='human'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({'id': 'preserved-human-id', 'author': author}))

    def check(passes, message=''):
        result = subprocess.run(['bash', str(rule)], cwd=root,
                                env={**os.environ, 'VIBEDECK_ROOT': str(root)},
                                capture_output=True, text=True)
        assert (result.returncode == 0) == passes, result.stdout + result.stderr
        assert message in result.stdout, result.stdout

    git('init', '-q')
    original = root / '.vibedeck/ideas/original.json'
    moved = root / '.vibedeck/ideas/pasta com espaço/novo.json'
    write(original)
    git('add', '.')
    git('-c', 'user.name=Teste', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'Fixture')
    check(True)
    moved.parent.mkdir(parents=True)
    original.rename(moved)
    check(True)  # O destino ainda não rastreado também preserva a identidade.
    git('add', '.')
    check(True)  # Movimento staged.
    write(moved, 'ai')
    check(False, 'deixou de ser author=human')
    write(moved)
    duplicate = root / '.vibedeck/ideas/copia.json'
    write(duplicate, 'ai')
    check(False, 'deixou de ser author=human')
    duplicate.unlink()
    moved.unlink()
    # Um check histórico contendo o ID não pode ocultar uma exclusão real.
    write(root / '.vibedeck/checks/historico.json')
    check(False, 'foi removido')
    write(moved)
    check(True)
print('7 cenários de preservação de itens humanos passaram.')
