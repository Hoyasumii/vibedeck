"""Offline rule checks: scoped UI contracts plus real ProjectModel Swift tests.

No cached verdicts or --skip-build: every applicable run tests the current code.
Unrecognized wiring fails closed and includes its source location for review.
"""
import os
from pathlib import Path
import re
import subprocess
import sys

APP = 'Sources/VibeDeckApp/'
CORE = 'Sources/VibeDeckCore/'
TEST = 'Tests/VibeDeckAppTests/RuleExecutionModelTests.swift'
WINDOW = APP + 'ProjectWindow.swift'
MODEL = APP + 'ProjectModel.swift'
PAGE = APP + 'SectionListView.swift'
HELPER = '.vibedeck/tests/painel-lateral-melhorado/'
scope = {WINDOW, MODEL, PAGE, CORE + 'Rules.swift', CORE + 'Models.swift', TEST,
         'Package.swift', 'Package.resolved'}
root = Path.cwd().resolve()
changed = os.environ.get('VIBEDECK_FILES', '').splitlines()
paths = []
for entry in changed:
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
    """Extract a balanced Swift block, skipping comments and string literals."""
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
    block = body(file, anchor)
    # Ignore comments, so a comment cannot satisfy a source contract.
    block = re.sub(r'//[^\n]*|/\*.*?\*/', '', block, flags=re.S)
    compact = re.sub(r'\s+', '', block)
    for fragment in fragments:
        if re.sub(r'\s+', '', fragment) not in compact:
            fail(file, anchor, f'ligação exigida ausente: {fragment}')
    return block


try:
    # Both sidebar sections must render precisely the IDs produced by the
    # behavior tested below, rather than duplicating a potentially different filter.
    sections = ['groups', 'ideas'] if rule in {'122bdd0c', '279a3ff7', '5e0c4b04'} else [
        'groups' if rule in {'e044fe9d', '48a075fc', '1409d15b'} else 'ideas']
    fragments = ['let visible = Set(model.sidebarRows(for: section, search: sidebarSearch).map(\\.id))']
    for section in sections:
        kind = 'group' if section == 'groups' else 'idea'
        fragments.append(f'ForEach(model.{section}.filter {{ visible.contains(.{kind}($0.slug)) }})')
    need(WINDOW, 'private func children(of section:', fragments)

    if rule in {'48a075fc', '605fc62c', '5e0c4b04'}:
        need(PAGE, 'private var allRows:', ['model.rows(for: section)'])
        need(PAGE, 'private var table:', ['Table(rows, selection: $selection)',
             'Button("Abrir") { onOpen(id) }',
             'Button("Abrir em Nova Aba") { onOpenInNewTab(id) }',
             'if let id = ids.first { onOpen(id) }'])
        need(WINDOW, 'private var detailContent:', [
             'SectionListView(section: section) { selection = $0 } onOpenInNewTab: { openInNewTab($0) }',
             'if model.group(slug) != nil { ReviewGroupView(slug: slug) }',
             'if model.idea(slug) != nil { IdeaView(slug: slug)'])
        need(WINDOW, 'private func openInNewTab(_ item:', [
             'tabs.insert(item, at: activeTab + 1)', 'activateTab(activeTab + 1)'])
        need(WINDOW, 'private func activateTab(_ index:', ['selection = tabs[index]'])

    if rule == '122bdd0c':
        need(WINDOW, '.onChange(of: selection)', [
             'guard let new else { selection = tabs[activeTab]; return }'])
        need(WINDOW, 'private func exists(_ item:', ['return model.exists(item)'])
        need(WINDOW, 'private func pruneTabs()', ['let kept = tabs.filter(exists)',
             'guard kept.count != tabs.count else { return }'])
        need(MODEL, 'func exists(_ item:', [
             'case .group(let slug): group(slug) != nil',
             'case .idea(let slug): idea(slug) != nil'])
        need(WINDOW, 'private var detailContent:', [
             'if model.group(slug) != nil { ReviewGroupView(slug: slug) }',
             'if model.idea(slug) != nil { IdeaView(slug: slug)'])
        for file, anchor in [(WINDOW, 'private func exists(_ item:'),
                             (WINDOW, 'private func pruneTabs()'),
                             (WINDOW, 'private var detailContent:'),
                             (MODEL, 'func exists(_ item:')]:
            if re.search(r'sidebarRows|openCount|\.done', body(file, anchor)):
                fail(file, anchor, 'validade de seleção/aba depende da visibilidade ou status')

    for name in tests[rule]:
        need(TEST, f'func {name}(', ['#expect('])
    expression = 'RuleExecutionModelTests/(' + '|'.join(tests[rule]) + ')'
    # Keep manifest/compiler caches inside the writable project, including when
    # launched by VibeDeck or an agent with a restricted home directory.
    cache = root / '.build' / 'ModuleCache'
    cache.mkdir(parents=True, exist_ok=True)
    environment = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(cache),
                   'SWIFTPM_MODULECACHE_OVERRIDE': str(cache)}
    # Python timeout includes SwiftPM lock waits and compilation. Offline: use
    # already resolved dependencies; missing dependencies are a failure, not a pass.
    try:
        result = subprocess.run(['swift', 'test', '--disable-sandbox', '--disable-automatic-resolution',
                                 '--filter', expression], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=110,
                                env=environment)
    except subprocess.TimeoutExpired as error:
        if error.stdout:
            print(error.stdout.decode(errors='replace') if isinstance(error.stdout, bytes) else error.stdout)
        fail(TEST, f'func {tests[rule][0]}(', 'verificação inconclusiva: Swift test excedeu 110 s')
    if result.returncode:
        print(result.stdout)
        fail(TEST, f'func {tests[rule][0]}(', f'Swift test falhou (exit {result.returncode})')
    for name in tests[rule]:
        if not re.search(r'Test ' + re.escape(name) + r'\(\) passed', result.stdout):
            print(result.stdout)
            fail(TEST, f'func {name}(', 'teste não executado/aprovado; resultado vazio não é evidência')
    print(f'{rule}: PASS — interface ligada ao modelo; {len(tests[rule])} teste(s) Swift aprovado(s)')
except (OSError, KeyError) as error:
    fail(MODEL, 'func sidebarRows(', f'verificação inconclusiva: {error}')
