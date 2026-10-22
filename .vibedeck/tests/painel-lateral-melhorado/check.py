"""Verificações offline das regras da coluna de conteúdo V2: contratos estáticos da interface e do modelo.

Sem veredito em cache. Ligação desconhecida falha (nunca aprova) e mostra o arquivo:linha. Quando `swift` está no
PATH (macOS), também roda os testes de V2ColumnVisibilityTests; no Linux só a análise estática vale (os testes
existem no código e a CI do macOS os executa).
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

APP = 'Sources/VibeDeckApp/'
TEST = 'Tests/VibeDeckAppTests/V2ColumnVisibilityTests.swift'
COLUMN = APP + 'V2/V2ContentColumn.swift'
WINDOW = APP + 'V2/V2ProjectWindow.swift'
MODEL = APP + 'ProjectModel.swift'
PAGE = APP + 'SectionListView.swift'
HELPER = '.vibedeck/tests/painel-lateral-melhorado/'
scope = {COLUMN, WINDOW, MODEL, PAGE, TEST, 'Package.swift', 'Package.resolved'}
root = Path.cwd().resolve()
paths = []
for entry in os.environ.get('VIBEDECK_FILES', '').splitlines():
    if not entry.strip():
        continue
    path = Path(entry.strip())
    if path.is_absolute():
        try:
            path = path.relative_to(root)
        except ValueError:
            continue
    paths.append(path.as_posix().removeprefix('./'))
if paths and not any(p in scope or p.startswith(HELPER) for p in paths):
    sys.exit(77)

rule = sys.argv[1]
tests = {
    'e044fe9d': ['sidebarGroupsUseOpenCountAndKeepSectionAccess'],
    '48a075fc': ['sidebarGroupsUseOpenCountAndKeepSectionAccess'],
    'e248d5a3': ['sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas'],
    '605fc62c': ['sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas'],
    '122bdd0c': ['sidebarSelectedTargetsRemainResolvableAcrossStatusChanges'],
    '279a3ff7': ['sidebarSearchFiltersVisibleRowsAcrossAllSections'],
    '1409d15b': ['sidebarGroupReappearsAfterUndoAndExternalEdit'],
    '5e0c4b04': ['sidebarGroupsUseOpenCountAndKeepSectionAccess',
                 'sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas',
                 'sidebarSearchFiltersVisibleRowsAcrossAllSections'],
    '7332715d': ['sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas'],
}


def fail(file, anchor, reason):
    source = Path(file).read_text() if Path(file).is_file() else ''
    offset = source.find(anchor)
    line = source[:max(offset, 0)].count('\n') + 1
    print(f'{file}:{line}: {rule}: {reason}', flush=True)
    sys.exit(1)


def body(file, anchor):
    """Bloco Swift balanceado a partir de `anchor`, ignorando comentários e strings."""
    source = Path(file).read_text()
    start = source.find(anchor)
    if start < 0:
        fail(file, anchor, f'bloco ausente: {anchor}')
    opening = source.find('{', start + len(anchor))
    pattern = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}]', re.S)
    depth = 0
    for token in pattern.finditer(source, opening):
        value = token.group()
        if value == '{':
            depth += 1
        elif value == '}':
            depth -= 1
            if depth == 0:
                return source[opening + 1:token.start()]
    fail(file, anchor, 'bloco Swift incompleto')


def need(file, anchor, fragments):
    block = re.sub(r'//[^\n]*|/\*.*?\*/', '', body(file, anchor), flags=re.S)
    compact = re.sub(r'\s+', '', block)
    for fragment in fragments:
        if re.sub(r'\s+', '', fragment) not in compact:
            fail(file, anchor, f'ligação exigida ausente: {fragment}')
    return block


try:
    # A coluna de conteúdo mostra exatamente o que o modelo decide omitir (sem filtro duplicado na view).
    need(COLUMN, 'private var allRows:', ['model.columnRows(for: $0, keeping: selection)'])
    need(MODEL, 'func columnRows(for section:', ['rows(for: section).filter', '$0.id == selected', '!isOmittedFromColumn($0.id)'])
    need(MODEL, 'func isOmittedFromColumn(', ['case .group(let slug): return (group(slug)?.openCount ?? 0) == 0',
                                              'case .idea(let slug): return idea(slug)?.status == .done',
                                              'default: return false'])
    # A coluna aplica o filtro de texto/#tag sobre as linhas que exibe.
    need(COLUMN, 'private var rows:', ['allRows.filter { filter.matches($0) }'])

    if rule in {'48a075fc', '605fc62c', '5e0c4b04'}:
        # A tabela do detalhe (seção) segue com a lista completa, sem a omissão.
        need(PAGE, 'private var allRows:', ['model.rows(for: section)'])
        need(PAGE, 'private var table:', ['Table(rows, selection: $selection)',
             'LoggedButton("Abrir") { onOpen(id) }',
             'LoggedButton("Abrir em Nova Aba") { onOpenInNewTab(id) }',
             'if let id = ids.first { onOpen(id) }'])
        need(WINDOW, 'private func sectionTable(', ['SectionListView(section: section, filter: $listFilter)'])
        need(WINDOW, 'private func itemDetail(', ['if model.group(slug) != nil { ReviewGroupView(slug: slug) }',
             'if model.idea(slug) != nil { IdeaView(slug: slug)'])
        need(WINDOW, 'private func openInNewTab(_ item:', ['tabs.append(item)', 'selection = item'])
        if 'columnRows' in body(PAGE, 'private var allRows:'):
            fail(PAGE, 'private var allRows:', 'a tabela do detalhe não pode aplicar a omissão da coluna')

    if rule == '122bdd0c':
        # Seleção e abas dependem de existir, nunca de visibilidade ou status.
        need(MODEL, 'func exists(_ item:', ['case .group(let slug): group(slug) != nil',
                                            'case .idea(let slug): idea(slug) != nil'])
        need(WINDOW, 'private func exists(_ item:', ['return model.exists(item)'])
        need(WINDOW, 'private func pruneSelection()', ['tabs.removeAll { !exists($0) }'])
        for file, anchor in [(WINDOW, 'private func exists(_ item:'), (WINDOW, 'private func pruneSelection()'),
                             (MODEL, 'func exists(_ item:')]:
            if re.search(r'columnRows|openCount|isOmittedFromColumn|\.done', body(file, anchor)):
                fail(file, anchor, 'validade de seleção/aba depende da visibilidade ou status')

    source = Path(TEST).read_text()
    for name in tests[rule]:
        if f'func {name}(' not in source:
            fail(TEST, name, f'teste {name} ausente')
        need(TEST, f'func {name}(', ['#expect('])
    if shutil.which('swift'):
        expression = 'V2ColumnVisibilityTests/(' + '|'.join(tests[rule]) + ')'
        cache = root / '.build' / 'ModuleCache'
        cache.mkdir(parents=True, exist_ok=True)
        environment = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(cache), 'SWIFTPM_MODULECACHE_OVERRIDE': str(cache)}
        try:
            result = subprocess.run(['swift', 'test', '--disable-sandbox', '--disable-automatic-resolution',
                                     '--filter', expression], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=110, env=environment)
        except subprocess.TimeoutExpired:
            fail(TEST, f'func {tests[rule][0]}(', 'verificação inconclusiva: swift test excedeu 110 s')
        if result.returncode:
            print(result.stdout)
            fail(TEST, f'func {tests[rule][0]}(', f'swift test falhou (exit {result.returncode})')
        print(f'{rule}: PASS — interface ligada ao modelo; {len(tests[rule])} teste(s) Swift aprovado(s)')
    else:
        print(f'{rule}: PASS — análise estática (sem swift neste ambiente; testes: {", ".join(tests[rule])})')
except (OSError, KeyError) as error:
    fail(MODEL, 'func columnRows(', f'verificação inconclusiva: {error}')
