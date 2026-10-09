"""Offline rule contracts plus fresh Swift tests; no provider is invoked.

Static contracts deliberately fail closed when a checked implementation changes.
They complement behavioral tests, rather than claiming to prove arbitrary Swift.
"""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import json

START = time.monotonic()
ROOT = Path(os.environ.get('VIBEDECK_ROOT') or '.').resolve()
os.chdir(ROOT)
RULE = sys.argv[1].upper()
APP = 'Sources/VibeDeckApp/'
CORE = 'Sources/VibeDeckCore/'
DG = APP + 'DocGenerate.swift'
CG = CORE + 'DocGenerate.swift'
PM = APP + 'ProjectModel.swift'
SL = APP + 'SectionListView.swift'
RO = APP + 'AIReadOnlyOperation.swift'
PS = CORE + 'ProjectStore.swift'
CR = CORE + 'ReviewDiscover.swift'
AR = APP + 'ReviewDiscover.swift'
CX = CORE + 'CodexReadOnly.swift'
CLI = 'Sources/vibedeck/CLI.swift'
MCP = 'Sources/vibedeck/MCPServer.swift'
CT = 'Tests/VibeDeckCoreTests/DocGenerateTests.swift'
AT = 'Tests/VibeDeckAppTests/DocGenerateTests.swift'
BASE = '.vibedeck/tests/botao-de-gerar-documentos/'
scope = {DG, CG, PM, SL, RO, PS, CR, AR, CX, CLI, MCP, CT, AT,
         'Package.swift', 'Package.resolved', 'README.md', '.vibedeck/guide.md',
         CORE + 'AIProvider.swift', CORE + 'CodexRPC.swift', CORE + 'AgentsGuide.swift',
         CORE + 'AIPromptPolicy.swift', CORE + 'AtomicFile.swift', CORE + 'Slug.swift',
         CORE + 'Stack.swift', CORE + 'RuleDiscover.swift', APP + 'RuleDiscover.swift',
         APP + 'DocView.swift', APP + 'MarkdownPreview.swift',
         'Tests/VibeDeckCoreTests/ReviewDiscoverTests.swift',
         'Tests/VibeDeckCoreTests/ProjectStoreTests.swift'}
changed = os.environ.get('VIBEDECK_FILES', '').splitlines()
normalized = set()
for item in changed:
    if not item.strip():
        continue
    path = Path(item.strip())
    if path.is_absolute():
        try:
            path = path.resolve().relative_to(ROOT)
        except ValueError:
            continue
    normalized.add(path.as_posix().removeprefix('./'))
if any(item.strip() for item in changed) and not any(p in scope or p.startswith(BASE) for p in normalized):
    sys.exit(77)

errors = []
def read(path):
    try:
        return Path(path).read_text()
    except OSError as error:
        errors.append(f'{path}:1: {error}')
        return ''

def need(path, pattern, reason, text=None):
    source = read(path) if text is None else text
    if not re.search(pattern, source, re.S):
        errors.append(f'{path}:1: {reason}')

def forbid(path, pattern, reason, text=None):
    source = read(path) if text is None else text
    match = re.search(pattern, source, re.S)
    if match:
        errors.append(f'{path}:{source[:match.start()].count(chr(10)) + 1}: {reason}')

def read_only():
    need(DG, r'AIReadOnlyOperation\.run\(', 'Geração deve usar AIReadOnlyOperation')
    forbid(DG, r'ClaudeStream|workspaceWrites\s*:\s*true|Process\(', 'Geração não pode contornar operação de leitura')
    need(RO, r'runner\.run\([^;]*?workspaceWrites:\s*false', 'Codex deve receber workspaceWrites=false')
    forbid(RO, r'workspaceWrites:\s*true|ClaudeStream', 'Operação de leitura não pode habilitar escrita')
    need(RO, r'ReviewDiscoverRunner\.run\(', 'Claude deve usar runner restrito')
    need(AR, r'process\.arguments = ReviewDiscover\.arguments\(\)', 'Runner deve usar argumentos restritos do Core')
    source = read(CR)
    tools = re.search(r'public static let tools\s*=\s*\[([^\]]*)\]', source)
    if not tools or sorted(re.findall(r'"([^\"]+)"', tools.group(1))) != ['Glob', 'Grep', 'Read']:
        errors.append(f'{CR}:1: somente Read, Glob, Grep são permitidos')
    need(CR, r'"--tools", tools, "--allowedTools", tools', 'Restringir ferramentas disponíveis e permitidas')
    need(CR, r'"--strict-mcp-config"', 'Não permitir ferramentas MCP externas')
    need(CX, r'"sandbox": \.string\(workspaceWrites \? "workspace-write" : "read-only"\)', 'Codex deve aplicar sandbox somente leitura')

def proposal():
    need(DG, r'@State private var documents: \[DocGenerate\.Document\]', 'Proposta deve ser estado local, sem autosave')
    need(DG, r'TextField\("Título", text: \$document.title\)', 'Título deve editar somente a proposta')
    need(DG, r'TextEditor\(text: \$document.content\)', 'Conteúdo deve editar somente a proposta')
    need(DG, r'Button\("Aceitar selecionados"\).*?accept\(documents.filter', 'Permitir aceite por documento')
    need(DG, r'Button\("Aceitar todos"\).*?accept\(documents\)', 'Permitir aceite de todos')
    need(DG, r'private func accept\(.*?model.acceptGeneratedDocs\(chosen, undo: undo\)', 'Somente aceite chama persistência')
    # Reject side effects anywhere in the proposal/runner, including change callbacks.
    forbid(DG, r'writeDoc\(|createDoc\(|createGeneratedDoc\(|deleteDoc\(|AtomicFile\.write|\.write\(to:|FileManager\.', 'Proposta não pode gravar/apagar arquivos')
    need(DG, r'private func close\(\) \{ runner.cancel\(\); dismiss\(\) \}', 'Cancelar deve apenas descartar proposta')
    need(PM, r'func acceptGeneratedDocs\(.*?store.createGeneratedDoc\(', 'Aceite deve persistir via Core')

tests = []
if RULE == '90397722':
    need(SL, r'if section == \.docs, !AIProvider.installed.isEmpty \{\s*ToolbarItemGroup \{\s*Button \{\s*model.docGenerator.start.*?Label\("Gerar documentos"', 'Botão deve ficar condicionado a Docs e provedor instalado')
    need(CORE + 'AIProvider.swift', r'case claude, codex', 'Provedores suportados devem ser Claude e Codex')
    need(CORE + 'AIProvider.swift', r'installed: \[AIProvider\] \{ allCases.filter\(\\.isInstalled\) \}', 'Disponibilidade deve filtrar provedores instalados')
elif RULE in {'83D8DA0A', '81D69362'}:
    read_only()
    if RULE == '83D8DA0A':
        # A filesystem sandbox prevents writes, but does not disable shell tools.
        # Fail closed until the Codex config explicitly disables its shell tool.
        need(CX, r'overrides\["features.shell_tool"\]\s*=\s*\.bool\(false\)',
             'Codex usa sandbox read-only, mas não bloqueia a ferramenta shell; a regra também proíbe Bash/comandos')
elif RULE in {'F0AAAB3E', '26B70328'}:
    proposal()
    tests = ['DocGenerateAppTests/proposalEditingAndCancellationNeverWrite', 'DocGenerateAppTests/selectedAcceptanceAndInvalidEdits']
elif RULE == 'FCF3BA40':
    need(PM, r'store.createGeneratedDoc\(title: document.title, body: document.content\)', 'Aceite deve usar Core')
    need(PS, r'func createGeneratedDoc\(.*?try createDoc\(title: title, body: body, author: \.ai\)', 'Documento gerado deve ter author=ai')
    need(CLI, r'struct Cat.*?options.store\(\).readDoc\(slug\)', 'CLI deve ler documentos do mesmo store')
    need(MCP, r'case "read_doc":\s*return try store.readDoc\(req\("slug"\)\)', 'MCP deve ler documentos do mesmo store')
    tests = ['DocGenerateTests/uniqueSlugsPreserveOriginalAndAuthor']
elif RULE == '778E9BF5':
    need(PS, r'func createDoc\(.*?uniqueSlug\(Slug.make\(title\), in: docsDir, ext: "md"\)', 'Criação deve usar Slug.make e uniqueSlug')
    tests = ['DocGenerateTests/uniqueSlugsPreserveOriginalAndAuthor']
elif RULE == 'DA211AC8':
    need(DG, r'parse: DocGenerate.parse', 'App deve validar a resposta no Core')
    need(DG, r'case \.failed\(let message\).*?description: Text\(message\)', 'Erro deve ser exibido ao usuário')
    need(PS, r'case \.docGenerationInvalidAnswer: "A IA retornou uma proposta de documentos inválida. Nenhum documento foi criado.', 'Mensagem clara em pt-BR deve afirmar que nenhum documento foi criado')
    tests = ['DocGenerateTests/strictJSONAndEmptyDocuments', 'DocGenerateAppTests/invalidAnswerAndMissingProviderCreateNothing']
elif RULE == '2CE9184C':
    need(SL, r'\.disabled\(model.docGenerator.isActive\)', 'Desabilitar geração durante operação ativa')
    need(SL, r'"Cancelar geração".*?model.docGenerator.cancel\(\)', 'Botão cancelar deve interromper geração')
    need(DG, r'guard !isActive else \{ return \}', 'Não permitir duas gerações ativas')
    need(DG, r'root.standardizedFileURL.resolvingSymlinksInPath\(\).path', 'Runner deve ser único por projeto canônico')
    need(DG, r'task\?\.cancel\(\)', 'Cancelar tarefa de geração')
    need(RO, r'timeout: \.seconds\(180\)', 'Codex deve ter timeout')
    need(AR, r'Task.sleep\(for: ReviewDiscover.timeout\).*?process.terminate\(\)', 'Claude deve encerrar processo no timeout')
    need(AR, r'onCancel: \{\s*if process.isRunning \{ process.terminate\(\)', 'Claude deve encerrar processo ao cancelar')
    need(CX, r'withTaskCancellationHandler.*?Task.sleep\(for: timeout\).*?onCancel:', 'Codex deve tratar timeout e cancelamento')
    tests = ['DocGenerateAppTests/proposalEditingAndCancellationNeverWrite', 'DocGenerateAppTests/timeoutShowsErrorWithoutCreatingDocs']
elif RULE == '205F9706':
    tests = ['DocGenerateAppTests/acceptingBatchUpdatesListAndIsOneUndoWithRedo']
elif RULE == '5DC6AE92':
    need(CG, r'public static func prompt\(', 'Prompt deve ficar no Core')
    need(CG, r'public static func parse\(', 'Parser deve ficar no Core')
    need(CG, r'public static func validated\(', 'Validador deve ficar no Core')
    forbid(CG, r'import SwiftUI', 'Core não pode depender de SwiftUI')
    need(DG, r'prompt: DocGenerate.prompt\(.*?schema: DocGenerate.schema.*?parse: DocGenerate.parse', 'App deve chamar prompt, schema e parser do Core')
    tests = ['DocGenerateTests/strictJSONAndEmptyDocuments', 'DocGenerateTests/limitsAndPrompt']
elif RULE == 'C5D852BD':
    tests = ['DocGenerateTests/strictJSONAndEmptyDocuments']
elif RULE == '9BDC1723':
    tests = ['DocGenerateTests/limitsAndPrompt']
elif RULE == '488ADC70':
    need(PS, r'func writeDoc\(.*?AtomicFile.write\(Data\(text.utf8\), to: docURL\(slug\)\)', 'Persistir formato existente usando AtomicFile.write')
    need(PS, r'func createDoc\(.*?try writeDoc\(slug, frontmatter', 'Criação deve usar a persistência atômica')
    need(PM, r'func acceptGeneratedDocs\(.*?reloadDocs\(\)', 'Aceite deve atualizar a lista imediatamente')
    tests = ['DocGenerateAppTests/acceptingBatchUpdatesListAndIsOneUndoWithRedo', 'DocGenerateTests/uniqueSlugsPreserveOriginalAndAuthor']
elif RULE == '8B870FEB':
    for path in ['README.md', '.vibedeck/guide.md', CORE + 'AgentsGuide.swift']:
        need(path, r'Gerar documentos', 'Documentação deve mencionar Gerar documentos')
        need(path, r'antes do aceite', 'Documentação deve explicar proposta e aceite')
    for label in ['Gerar documentos', 'Lendo o projeto e propondo documentos…', 'Não foi possível gerar documentos', 'Cancelar geração', 'Aceitar todos', 'Aceitar selecionados', 'Título']:
        need(DG if label != 'Gerar documentos' else SL, re.escape('"' + label + '"'), 'Texto visível esperado em pt-BR: ' + label)
    need(PS, r'A IA retornou uma proposta de documentos inválida', 'Erro de JSON deve estar em pt-BR')
    # Reviewed Portuguese copy. Unknown copy fails closed, including new controls.
    portuguese = {
        r'\(provider.title) não está instalado. Selecione um provedor disponível no painel IA.',
        'Gerar documentos', 'Lendo o projeto e propondo documentos…',
        'Nada será gravado antes do seu aceite.', 'Não foi possível gerar documentos',
        'Nenhum documento proposto', 'A IA não encontrou conteúdo novo dentro dos limites da geração.',
        'Revise os documentos. Editar ou descartar aqui não altera arquivos.',
        'Aceitar', 'Editar', 'Pré-visualizar', 'Descartar', 'Título',
        'Informe título e conteúdo; o conteúdo deve ter até 40.000 caracteres.',
        'Cancelar geração', 'Cancelar', 'Aceitar selecionados', 'Aceitar todos',
    }
    noncopy = {'exclamationmark.triangle', 'doc.text', r'# \(document.title)\n\n\(document.content)'}
    source = read(DG)
    for match in re.finditer(r'"(?:[^"\\]|\\.)*"', source):
        if match.group()[1:-1] not in portuguese | noncopy:
            line = source[:match.start()].count('\n') + 1
            errors.append(f'{DG}:{line}: texto novo sem contrato de pt-BR: {match.group()}')
else:
    errors.append(f'{BASE}_check.py:1: regra desconhecida: {RULE}')

if errors:
    print('\n'.join(errors))
    sys.exit(1)
if tests:
    # Refuse to fetch missing packages. Resolution is disabled below as well.
    try:
        workspace = json.loads((ROOT / '.build' / 'workspace-state.json').read_text())
        pins = json.loads((ROOT / 'Package.resolved').read_text())['pins']
        dependencies = workspace['object']['dependencies']
        cached = {dep['packageRef']['identity']: dep for dep in dependencies}
        for pin in pins:
            dep = cached[pin['identity']]
            if dep['state']['checkoutState']['revision'] != pin['state']['revision']:
                raise ValueError('checkout desatualizado: ' + pin['identity'])
            if not (ROOT / '.build' / 'checkouts' / dep['subpath'] / 'Package.swift').is_file():
                raise ValueError('checkout ausente: ' + pin['identity'])
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Package.resolved:1: dependências locais necessárias para teste sem rede: {error}')
        sys.exit(1)
    # Build each time: --skip-build could approve stale code. No dependency fetching.
    pattern = '|'.join(re.escape(test) for test in tests)
    # The host already sandboxes this script; nested sandbox-exec is unavailable.
    command = ['swift', 'test', '--disable-sandbox', '--disable-automatic-resolution', '--skip-update',
               '--manifest-cache', 'local', '--cache-path', str(ROOT / '.build' / 'doc-rule-package-cache'),
               '--filter', pattern]
    cache = ROOT / '.build' / 'doc-rule-module-cache'
    cache.mkdir(parents=True, exist_ok=True)
    # Foundation usage records and UserDefaults must stay isolated from real user data.
    test_home = ROOT / '.build' / 'doc-rule-user'
    (test_home / 'Library' / 'Application Support').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, NO_COLOR='1', CLANG_MODULE_CACHE_PATH=str(cache),
               SWIFTPM_MODULECACHE_OVERRIDE=str(cache), CFFIXED_USER_HOME=str(test_home))
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, env=env, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=max(1, 110 - (time.monotonic() - START)))
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            print(output)
            print(f'{AT if "AppTests" in pattern else CT}:1: verificação excedeu 110s; não foi aprovada')
            sys.exit(1)
    except OSError as error:
        print(f'Package.swift:1: não foi possível executar Swift: {error}')
        sys.exit(1)
    # Swift can exit 0 when a filter matches no tests: require every selected test.
    missing = [test for test in tests if not re.search(r'Test ' + re.escape(test.split('/')[1]) + r'\(\) passed', output)]
    if process.returncode != 0 or missing:
        print(output)
        print(f'{AT if "AppTests" in pattern else CT}:1: teste falhou ou não foi executado: {", ".join(missing) or RULE}')
        sys.exit(1)
print(f'{RULE}: cumpre (contratos de código' + (f'; {len(tests)} testes Swift passaram)' if tests else ')'))
