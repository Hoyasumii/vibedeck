"""Contratos offline das regras do botão de gerar documentos, mais testes Rust/CLI atuais; nenhum provedor de IA é chamado.

Os contratos estáticos falham fechados quando o código verificado muda. Complementam os testes de
comportamento, sem pretender provar código arbitrário. O Core, o CLI e o MCP são Rust (crates/); a tela e o
executor de IA do app são Swift (Sources/VibeDeckApp).
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

START = time.monotonic()
ROOT = Path(os.environ.get('VIBEDECK_ROOT') or '.').resolve()
os.chdir(ROOT)
RULE = sys.argv[1].upper()
APP = 'Sources/VibeDeckApp/'
APPCORE = APP + 'Core/'
DG = APP + 'DocGenerate.swift'
PM = APP + 'ProjectModel.swift'
SL = APP + 'SectionListView.swift'
RO = APP + 'AIReadOnlyOperation.swift'
AR = APPCORE + 'AI/AIReadOnlyProcess.swift'  # processo restrito do claude (antes ReviewDiscoverRunner.run)
CR = APPCORE + 'Discover/ReviewDiscoverLogic.swift'
CX = APPCORE + 'AI/CodexReadOnly.swift'
CRATE = 'crates/vibedeck-core/src/'
GEN = CRATE + 'docs/generate.rs'
DOCS = CRATE + 'docs/mod.rs'
DERR = CRATE + 'docs/error.rs'
PROC = CRATE + 'ai/process.rs'
CODEX = CRATE + 'ai/codex.rs'
PROV = CRATE + 'ai/provider.rs'
GUIDE = CRATE + 'ai/guide_reference.md'
CLI = 'crates/vibedeck/src/cli/docs.rs'
MCP = 'crates/vibedeck/src/mcp/tools/docs.rs'
BIN = 'target/debug/vibedeck'
BASE = '.vibedeck/tests/botao-de-gerar-documentos/'
scope = {DG, PM, SL, RO, AR, CR, CX, GEN, DOCS, DERR, PROC, CODEX, PROV, GUIDE, CLI, MCP,
         'Cargo.toml', 'Cargo.lock', 'README.md', '.vibedeck/guide.md',
         'crates/vibedeck-core/src/slug.rs', 'crates/vibedeck-core/src/store.rs',
         APP + 'DocView.swift', APP + 'MarkdownPreview.swift',
         APPCORE + 'Discover/DocGenerateLogic.swift', APPCORE + 'AI/AIProvider.swift'}
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
    # App: a operação compartilhada de leitura.
    need(DG, r'AIReadOnlyOperation\.run\(', 'Geração deve usar AIReadOnlyOperation')
    forbid(DG, r'ClaudeStream|workspaceWrites\s*:\s*true|Process\(', 'Geração não pode contornar operação de leitura')
    need(RO, r'runner\.run\([^;]*?workspaceWrites:\s*false', 'Codex deve receber workspaceWrites=false')
    forbid(RO, r'workspaceWrites:\s*true|ClaudeStream', 'Operação de leitura não pode habilitar escrita')
    need(RO, r'AIReadOnlyProcess\.run\(', 'Claude deve usar runner restrito')
    need(AR, r'process\.arguments = ReviewDiscover\.arguments\(\)', 'Runner deve usar argumentos restritos')
    source = read(CR)
    tools = re.search(r'static let tools\s*=\s*\[([^\]]*)\]', source)
    if not tools or sorted(re.findall(r'"([^\"]+)"', tools.group(1))) != ['Glob', 'Grep', 'Read']:
        errors.append(f'{CR}:1: somente Read, Glob, Grep são permitidos')
    need(CR, r'"--tools", tools, "--allowedTools", tools', 'Restringir ferramentas disponíveis e permitidas')
    need(CR, r'"--strict-mcp-config"', 'Não permitir ferramentas MCP externas')
    need(CX, r'"sandbox": \.string\(workspaceWrites \? "workspace-write" : "read-only"\)', 'Codex deve aplicar sandbox somente leitura')
    # Core Rust: o mesmo contrato no processo do Claude e no Codex.
    source = read(PROC)
    tools = re.search(r'pub const TOOLS: \[&str; \d+\] = \[([^\]]*)\];', source)
    if not tools or sorted(re.findall(r'"([^"]+)"', tools.group(1))) != ['Glob', 'Grep', 'Read']:
        errors.append(f'{PROC}:1: somente Read, Grep, Glob são permitidos')
    need(PROC, r'"--tools",\s*&tools,\s*"--allowedTools",\s*&tools', 'Restringir ferramentas disponíveis e permitidas (Core Rust)')
    need(PROC, r'"--strict-mcp-config"', 'Não permitir ferramentas MCP externas (Core Rust)')
    need(CODEX, r'"sandbox": "read-only"', 'Codex deve aplicar sandbox somente leitura (Core Rust)')
    forbid(CODEX, r'workspace-write', 'O Core Rust não pode habilitar escrita no workspace do Codex')

def proposal():
    need(DG, r'@State private var documents: \[DocGenerate\.Document\]', 'Proposta deve ser estado local, sem autosave')
    need(DG, r'TextField\("Título", text: \$document.title\)', 'Título deve editar somente a proposta')
    need(DG, r'TextEditor\(text: \$document.content\)', 'Conteúdo deve editar somente a proposta')
    need(DG, r'Button\("Aceitar selecionados"\).*?accept\(documents.filter', 'Permitir aceite por documento')
    need(DG, r'Button\("Aceitar todos"\).*?accept\(documents\)', 'Permitir aceite de todos')
    need(DG, r'private func accept\(.*?model.acceptGeneratedDocs\(', 'Somente aceite chama persistência')
    # Reject side effects anywhere in the proposal/runner, including change callbacks.
    forbid(DG, r'writeDoc\(|createDoc\(|createGeneratedDoc\(|deleteDoc\(|AtomicFile\.write|\.write\(to:|FileManager\.', 'Proposta não pode gravar/apagar arquivos')
    need(DG, r'private func close\(\) \{ runner.cancel\(\); dismiss\(\) \}', 'Cancelar deve apenas descartar proposta')
    need(PM, r'func acceptGeneratedDocs\(.*?store\.createDoc\([^)]*generated: true\)', 'Aceite deve persistir via Core (create_doc com autoria ai)')

def cargo_test(test_file, names):
    """Roda só os testes Rust pedidos (cargo, offline); exige que cada um exista e passe."""
    scope = ['--lib'] if test_file.startswith(CRATE) else ['--test', Path(test_file).stem]
    for name in names:
        if not re.search(r'fn ' + re.escape(name) + r'\(', read(test_file)):
            errors.append(f'{test_file}:1: teste {name} não existe')
    if errors:
        return
    result = subprocess.run(['cargo', 'test', '--offline', '-q', '-p', 'vibedeck-core', *scope, '--', *names],
                            capture_output=True, text=True)
    out = result.stdout + result.stderr
    if result.returncode != 0 or not re.search(r'test result: ok\. [1-9]\d* passed', out):
        errors.append(out[-3000:] + f'\n{test_file}:1: teste falhou ou não foi executado: {", ".join(names)}')

def generated_docs_roundtrip():
    """Comportamento pelo binário: dois docs gerados (--ai) com o mesmo título viram dois slugs, o original fica
    intacto e os dois têm author: ai no frontmatter; o CLI lê o que o Core gravou."""
    build = subprocess.run(['cargo', 'build', '-q', '-p', 'vibedeck', '--offline'], capture_output=True, text=True)
    if build.returncode != 0:
        errors.append(build.stdout[-2000:] + build.stderr[-2000:] + '\ncrates/vibedeck:1: o CLI não compilou')
        return
    binary = str(ROOT / BIN)
    tmp = Path(tempfile.mkdtemp(prefix='vd-docgen-'))
    try:
        (tmp / 'vibedeck.json').write_text('{}')
        def run(*args):
            return subprocess.run([binary, *args], cwd=tmp, capture_output=True, text=True)
        first = run('docs', 'new', 'Título', '--body', 'Original', '--ai')
        second = run('docs', 'new', 'Título', '--body', 'Gerado depois', '--ai')
        slugs = (first.stdout.strip(), second.stdout.strip())
        if first.returncode or second.returncode or slugs[0] == slugs[1] or not all(slugs):
            errors.append(f'{CLI}:1: geração repetida com o mesmo título deve dar slugs distintos (obtive {slugs}; {first.stderr}{second.stderr})')
            return
        original = run('docs', 'cat', slugs[0]).stdout
        later = run('docs', 'cat', slugs[1]).stdout
        if 'Original' not in original or 'Gerado depois' in original:
            errors.append(f'{DOCS}:1: o documento original foi sobrescrito: {original!r}')
        for slug in slugs:
            text = (tmp / '.vibedeck' / 'docs' / f'{slug}.md').read_text()
            if not text.startswith('---\nauthor: ai\n---\n'):
                errors.append(f'{DOCS}:1: o documento {slug} não tem author: ai no frontmatter: {text[:60]!r}')
        if 'Gerado depois' not in later:
            errors.append(f'{CLI}:1: o CLI não leu o documento gerado {slugs[1]}')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

tests = []
if RULE == '90397722':
    need(SL, r'if section == \.docs, !AIProvider\.installed(?:\(in: providerRoot\))?\.isEmpty \{\s*ToolbarItemGroup \{\s*Button \{\s*model.docGenerator.start.*?Label\("Gerar documentos"', 'Botão deve ficar condicionado a Docs e provedor instalado')
    need(PROV, r'pub enum Provider \{\s*Claude,\s*Codex,\s*\}', 'Provedores suportados devem ser Claude e Codex')
    forbid(PROV, r'pub enum Provider \{[^}]*,\s*\w+,\s*\w+,', 'Só Claude e Codex são provedores suportados')
    need(PROV, r'pub fn executable\(self\) -> Option<PathBuf>', 'Disponibilidade deve vir da detecção do executável instalado')
elif RULE in {'83D8DA0A', '81D69362'}:
    read_only()
    if RULE == '83D8DA0A':
        # O sandbox impede escrita, mas não desliga ferramentas de shell: o Core Rust as desliga explicitamente.
        need(CODEX, r'overrides\.insert\("features\.shell_tool"\.into\(\), Value::Bool\(false\)\)',
             'Codex usa sandbox read-only, mas não bloqueia a ferramenta shell; a regra também proíbe Bash/comandos')
        need(CX, r'overrides\["features.shell_tool"\]\s*=\s*\.bool\(false\)', 'O executor do app também deve bloquear a ferramenta shell')
elif RULE in {'F0AAAB3E', '26B70328'}:
    proposal()
elif RULE == 'FCF3BA40':
    need(PM, r'store\.createDoc\(title: document\.title, body: document\.content, reference: reference, generated: true\)', 'Aceite deve usar o Core com autoria ai')
    need(DOCS, r'pub fn create_generated_doc\(.*?create_doc\(store, title, body, Author::Ai, reference\)', 'Documento gerado deve ter author=ai')
    need(MCP, r'args\.bool\("generated"\) == Some\(true\).*?Author::Ai', 'MCP write_doc generated deve gravar author=ai')
    need(CLI, r'Some\(DocsCommand::Cat \{ slug \}\) => \{\s*print!\("\{\}", docs::read_doc\(&ctx\.store\(\)\?, &slug\)\?\)', 'CLI deve ler documentos do mesmo store')
    need(MCP, r'"read_doc".*?docs::read_doc\(&ctx\.store\(\)\?', 'MCP deve ler documentos do mesmo store')
    if not errors:
        generated_docs_roundtrip()
elif RULE == '778E9BF5':
    need(DOCS, r'pub fn create_doc\(.*?slug::unique\(&slug::make\(title\), &dir, "md"\)', 'Criação deve usar slug::make e slug::unique')
    if not errors:
        generated_docs_roundtrip()
elif RULE == 'DA211AC8':
    need(DG, r'parse: DocGenerate.parse', 'App deve validar a resposta no parser do Core')
    need(DG, r'case \.failed\(let message\).*?description: Text\(message\)', 'Erro deve ser exibido ao usuário')
    need(GEN, r'pub fn parse\(data: &\[u8\]\) -> Result<Vec<Document>>.*?DocError::InvalidAnswer', 'O parser do Core deve rejeitar resposta inválida')
    need(DERR, r'"A IA retornou uma proposta de documentos inválida\. Nenhum documento foi criado\.', 'Mensagem clara em pt-BR deve afirmar que nenhum documento foi criado')
    if not errors:
        cargo_test(GEN, ['strict_json_and_empty_documents'])
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
    # Core Rust: prazo de 180 s e o processo do grupo morto no estouro.
    need(PROC, r'pub const DISCOVER_TIMEOUT: Duration = Duration::from_secs\(180\);', 'O Core deve ter prazo de 180 s')
    need(PROC, r'if Instant::now\(\) >= deadline \{.*?killpg\(child\.id\(\) as i32, libc::SIGKILL\)', 'O Core deve matar o processo ao estourar o prazo')
    need(CODEX, r'let deadline = Instant::now\(\) \+ timeout;', 'O Codex do Core deve ter prazo')
elif RULE == '205F9706':
    need(PM, r'undo\?\.registerUndo\(withTarget: self\).*?toggleGeneratedDocs\(snapshot, remove: true', 'Aceitar o lote deve registrar um único undo')
    need(PM, r'undo\?\.setActionName\("Gerar documentos"\)', 'O undo do lote deve ter nome')
elif RULE == '5DC6AE92':
    need(GEN, r'pub fn prompt\(', 'Prompt deve ficar no Core')
    need(GEN, r'pub fn parse\(', 'Parser deve ficar no Core')
    need(GEN, r'pub fn validated\(', 'Validador deve ficar no Core')
    need(GEN, r'pub const SCHEMA: &str', 'Schema deve ficar no Core')
    forbid(GEN, r'SwiftUI|\buse (std::fs|std::process)\b|AtomicFile|write_atomic', 'A lógica pura de propostas não pode depender de UI, disco ou processos')
    need(GEN, r'#\[cfg\(test\)\]\s*mod tests', 'O módulo do Core deve ter testes de unidade')
    need(DG, r'prompt: DocGenerate.prompt\(.*?schema: DocGenerate.schema.*?parse: DocGenerate.parse', 'App deve chamar prompt, schema e parser de DocGenerate')
    if not errors:
        cargo_test(GEN, ['strict_json_and_empty_documents', 'limits_and_prompt'])
elif RULE == 'C5D852BD':
    need(GEN, r'!title\.is_empty\(\)\s*&& !content\.is_empty\(\)', 'O validador deve descartar título/conteúdo vazios após trim')
    cargo_test(GEN, ['strict_json_and_empty_documents'])
elif RULE == '9BDC1723':
    need(GEN, r'pub const MAX_DOCUMENTS: usize = 8;', 'Limite de 8 documentos')
    need(GEN, r'\.take\(MAX_DOCUMENTS\)', 'O excedente deve ser descartado')
    cargo_test(GEN, ['limits_and_prompt'])
elif RULE == '488ADC70':
    need(DOCS, r'pub fn write_doc\(.*?DocFile::Regular\(p\) => write_atomic\(&p, text\.as_bytes\(\)\)', 'Persistir formato existente usando write_atomic')
    need(DOCS, r'pub fn create_doc\(.*?write_doc\(store, &slug, &format!\("\{frontmatter\}# \{title\}\\n\\n\{body\}"\)\)', 'Criação deve usar a persistência atômica')
    need(PM, r'func acceptGeneratedDocs\(.*?refreshDocs\(\)', 'Aceite deve atualizar a lista imediatamente')
    if not errors:
        generated_docs_roundtrip()
elif RULE == '8B870FEB':
    for path in ['README.md', '.vibedeck/guide.md', GUIDE]:
        need(path, r'Gerar documentos', 'Documentação deve mencionar Gerar documentos')
        need(path, r'antes do aceite', 'Documentação deve explicar proposta e aceite')
    for label in ['Gerar documentos', 'Lendo o projeto e propondo documentos…', 'Não foi possível gerar documentos', 'Cancelar geração', 'Aceitar todos', 'Aceitar selecionados', 'Título']:
        need(DG if label != 'Gerar documentos' else SL, re.escape('"' + label + '"'), 'Texto visível esperado em pt-BR: ' + label)
    need(DERR, r'A IA retornou uma proposta de documentos inválida', 'Erro de JSON deve estar em pt-BR')
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
print(f'{RULE}: cumpre (contratos de código' + (f'; {len(tests)} testes passaram)' if tests else ')'))
