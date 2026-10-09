#!/usr/bin/env python3
"""Offline rule checks. Unknown implementation shapes fail closed, never approve.

Static checks enforce explicit source contracts; AppKit checks compile the actual
editor in isolation, without resolving SwiftPM packages or altering the clipboard.
"""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

START = time.monotonic()
ROOT = Path(os.environ.get("VIBEDECK_ROOT") or ".").resolve()
os.chdir(ROOT)
RULE = sys.argv[1].upper()
BASE = "Sources/VibeDeckApp/"
EDITOR = BASE + "MarkdownEditor.swift"
PREVIEW = BASE + "MarkdownPreview.swift"
DOC = BASE + "DocView.swift"
IDEA = BASE + "IdeaView.swift"
COMMON = {EDITOR, PREVIEW, DOC, IDEA, "Package.swift"}
EXTRA = {
    "F8FDC0F6": {BASE + "ProjectModel.swift", "Sources/VibeDeckCore/ProjectStore.swift"},
    "BF5BA615": {BASE + "DocGenerate.swift", "Package.resolved"},
    "DB31B66D": {BASE + "DocGenerate.swift", "Package.resolved"},
    "5C7F52C8": {"Package.resolved"},
    "ADA320A2": {BASE + "ProjectModel.swift"},
    "A1657562": {BASE + name + "View.swift" for name in ["Agent", "Command", "Skill"]},
}
changed = []
for item in os.environ.get("VIBEDECK_FILES", "").splitlines():
    if not item.strip():
        continue
    path = Path(item.strip())
    try:
        changed.append((path if path.is_absolute() else ROOT / path).resolve().relative_to(ROOT).as_posix())
    except ValueError:
        changed.append(item)
if changed and not any(p in COMMON | EXTRA.get(RULE, set()) or
                       p.startswith(("Tests/VibeDeckAppTests/", ".vibedeck/tests/melhorar-o-md-viewer/"))
                       for p in changed):
    sys.exit(77)


def source(path):
    try:
        return (ROOT / path).read_text()
    except OSError as error:
        fail(path, "", str(error))


def fail(path, needle, reason):
    text = (ROOT / path).read_text() if (ROOT / path).is_file() else ""
    offset = text.find(needle) if needle else -1
    line = text.count("\n", 0, offset) + 1 if offset >= 0 else 1
    print(f"{path}:{line}: {reason}", flush=True)
    sys.exit(1)


def require(path, pattern, reason):
    if not re.search(pattern, source(path), re.S):
        fail(path, "", reason)


def block(text, anchor):
    """Balanced declaration body; braces inside Swift strings/comments ignored."""
    match = re.search(anchor, text)
    if not match:
        return ""
    start = text.find("{", match.end())
    if start < 0:
        return ""
    tokens = re.compile(r'//[^\n]*|/\*.*?\*/|#+".*?"#+|"(?:\\.|[^"\\])*"|[{}]', re.S)
    depth = 0
    for token in tokens.finditer(text, start):
        if token.group() == "{":
            depth += 1
        elif token.group() == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:token.start()]
    return ""


def single_surface():
    make = block(source(EDITOR), r"func makeNSView\([^)]*\)\s*->\s*NSScrollView")
    if len(re.findall(r"\b(?:AttachmentTextView|NSTextView)(?:\.markdownView)?\s*\(", make)) != 1:
        fail(EDITOR, "func makeNSView", "a edição deve criar exatamente um NSTextView")
    for pattern in [r"scrollView\.documentView\s*=\s*textView", r"textView\.delegate\s*=\s*context\.coordinator"]:
        if not re.search(pattern, make):
            fail(EDITOR, "func makeNSView", "texto editável e estilização devem usar o mesmo text storage")
    require(EDITOR, r"MarkdownHighlighter\.apply\(to:\s*storage", "o storage editado não recebe a renderização")
    require(EDITOR, r"(?:textView\.textStorage\?\.delegate\s*=\s*context\.coordinator|context\.coordinator\.textView\s*=\s*textView)", "coordinator não está ligado ao storage da view editável")
    for path in [DOC, IDEA]:
        require(path, r"private var mode:\s*MarkdownViewMode\s*=\s*\.edit", "modo padrão precisa ser edição")
        content = block(source(path), r"private var content:\s*some View")
        edit = re.search(r"case\s+\.edit:\s*(.*?)\s*case\s+\.", content, re.S)
        if not edit or edit.group(1).strip() != "editor":
            fail(path, "case .edit:", "modo de edição precisa montar apenas o editor, sem preview paralelo")
        view = block(source(path), r"private var editor:\s*some View")
        if view.count("MarkdownEditor(") != 1 or "MarkdownPreview(" in view:
            fail(path, "private var editor", "editor deve conter uma única view editável")


def no_background(paths):
    for path in paths:
        text = source(path)
        # Skip line comments, preserving diagnostic line positions.
        code = re.sub(r"//[^\n]*", "", text)
        patterns = [r"\.markdownTheme\s*\(\s*\.gitHub\s*\)",
                    r"\.background\s*\(\s*(?:Color\b|NSColor\b|\.(?!clear\b)[a-zA-Z])",
                    r"\bBackgroundColor\s*\(\s*(?!nil\b)",
                    r"\b(?:textView|scrollView)\.drawsBackground\s*=\s*true",
                    r"\.backgroundColor\s*(?:=|:)\s*(?!NSColor\.clear\b|\.clear\b)[^\s,\]]"]
        for pattern in patterns:
            match = re.search(pattern, code)
            if match:
                fail(path, match.group(), "fundo próprio/tema com fundo distinto do contexto da janela")
        for theme in re.findall(r"\.markdownTheme\s*\(\s*\.([A-Za-z]+)\s*\)", code):
            # Validate the actual locally resolved theme as well as the view.
            dependency = ".build/checkouts/swift-markdown-ui/Sources/MarkdownUI/Theme/Theme+" + theme[0].upper() + theme[1:] + ".swift"
            theme_code = re.sub(r"//[^\n]*", "", source(dependency))
            if re.search(r"BackgroundColor\s*\(\s*(?!nil\b)|\.background\s*\(|markdownTableBackgroundStyle", theme_code):
                fail(path, ".markdownTheme", f"tema {theme} define fundo próprio ({dependency})")
    if EDITOR in paths:
        for view in ["textView", "scrollView"]:
            require(EDITOR, rf"{view}\.drawsBackground\s*=\s*false", f"{view} deve herdar o fundo da janela")


def run(command, env=None):
    # A single wall-clock budget includes compilation and execution; no network.
    remaining = 110 - (time.monotonic() - START)
    if remaining <= 0:
        fail(EDITOR, "", "verificação excedeu orçamento de 110 s")
    process = None
    try:
        process = subprocess.Popen(command, env=env, start_new_session=True)
        status = process.wait(timeout=remaining)
    except (OSError, subprocess.TimeoutExpired) as error:
        if process is not None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        fail(EDITOR, "", f"verificação não concluída: {error}")
    if status:
        fail(EDITOR, "", f"verificação retornou {status}")


def appkit(mode):
    with tempfile.TemporaryDirectory(prefix="vibedeck-markdown-") as directory:
        directory = Path(directory)
        (directory / "MarkdownEditor.swift").write_text(source(EDITOR))
        preview = source(PREVIEW)
        loader = block(preview, r"enum MarkdownImageLoader")
        if loader:
            (directory / "MarkdownImageLoader.swift").write_text("import AppKit\n@MainActor enum MarkdownImageLoader {\n" + loader + "\n}\n")
        (directory / "main.swift").write_text(source(".vibedeck/tests/melhorar-o-md-viewer/appkit.swift"))
        run(["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", str(directory / "cache"),
             *map(str, sorted(directory.glob("*.swift"))), "-o", str(directory / "check")])
        run([str(directory / "check"), mode])


if RULE in {"0DD08791", "6B1849E4"}:
    single_surface()
elif RULE == "F8FDC0F6":
    # Persistence paths must forward the unmodified binding, in addition to the
    # actual NSTextView/highlighter runtime round-trip below.
    require(DOC, r"model\.saveDoc\(slug, text: text\)", "save() deve persistir o binding sem transformação")
    require(BASE + "ProjectModel.swift", r"func saveDoc\(.*?write\(Data\(text\.utf8\), to: store\.docURL\(slug\)\)", "saveDoc deve gravar os bytes markdown originais")
    require(IDEA, r"let body = text.*?\$0\.body = body\.isEmpty \? nil : body", "save() da ideia deve preservar o markdown")
    appkit("raw")
elif RULE == "501B105D":
    appkit("cursor")
elif RULE == "DB31B66D":
    no_background([EDITOR, PREVIEW, DOC, IDEA])
elif RULE == "BF5BA615":
    no_background([PREVIEW, BASE + "DocGenerate.swift"])
elif RULE == "D4086F37":
    # Current editor has neither URL context nor inline image rendering. These
    # are necessary conditions; don't confuse preview images with WYSIWYG ones.
    text = source(EDITOR)
    if not re.search(r"\b(?:baseURL|docsDir|ideasDir)\b", text):
        fail(EDITOR, "struct MarkdownEditor", "editor não recebe baseURL/docsDir/ideasDir para resolver anexos relativos")
    if not re.search(r"NSTextAttachment|attachmentCell|image\.draw\(|NSImage\(contentsOf:", text):
        fail(EDITOR, "enum MarkdownHighlighter", "editor não possui renderização inline de imagens")
    for path, directory in [(DOC, "docsDir"), (IDEA, "ideasDir")]:
        body = block(source(path), r"private var editor:\s*some View")
        if f"baseURL: model.store.{directory}" not in body:
            fail(path, "private var editor", "base de anexos não é passada ao editor WYSIWYG")
    appkit("images")
elif RULE == "27AC8B98":
    text = source(EDITOR)
    delegate = block(text, r"func textStorage\(")
    apply = block(text, r"static func apply\(")
    if "MarkdownHighlighter.apply(to: storage)" in delegate and re.search(r"enumerateMatches\(in:\s*string,\s*range:\s*full", apply):
        fail(EDITOR, "MarkdownHighlighter.apply(to: storage)", "cada edição executa regex síncrona no documento inteiro, ignorando range/delta")
    # Accept an explicit edited-range pipeline or an asynchronous renderer.
    # Merely deleting rendering must not pass the performance contract.
    incremental = re.search(r"MarkdownHighlighter\.apply\([^)]*\brange:\s*range", delegate) and not re.search(r"range:\s*full", apply)
    scheduler = block(text, r"private func scheduleRender\(\)")
    did_change = block(text, r"func textDidChange\(")
    asynchronous = "scheduleRender()" in did_change and re.search(r"DispatchQueue\.main\.async\s*\{[\s\S]*self\.render\(range\)", scheduler)
    if not (incremental or asynchronous):
        fail(EDITOR, "func textStorage", "não há evidência de renderização por range editado ou fora do caminho síncrono de digitação")
    appkit("large")
elif RULE == "ADA320A2":
    for pattern, reason in [
        (r"textView\.allowsUndo\s*=\s*true", "undo nativo desabilitado"),
        (r"func undoManager\(for view: NSTextView\).*?parent\.undoManager", "delegate não usa UndoManager do documento"),
        (r"override func performDragOperation.*?insertBlock\(importFiles\(urls\)", "drag não importa e insere anexos"),
        (r"override func paste.*?(?:pasteContents\(of: \.general\)|let pasteboard = NSPasteboard\.general)", "paste nativo não usa o importador de anexos"),
        (r"(?:func pasteContents|override func paste).*?insertBlock\(importFiles\(urls\)", "paste não importa e insere arquivos"),
        (r"(?:func pasteContents|override func paste).*?importImage\(data\).*?insertBlock\(link\)", "paste não importa imagens"),
        (r"insertion\.id != context\.coordinator\.lastInsertion.*?textView\.insertBlock\(insertion\.text\)", "inserção do botão não passa pelo editor"),
        (r"shouldChangeText\(in: full, replacementString: text\).*?replaceCharacters\(in: full, with: text\).*?didChangeText\(\).*?setActionName\(\"Alteração externa\"\)", "mudança externa não usa edição desfazível")]:
        require(EDITOR, pattern, reason)
    for path in [DOC, IDEA]:
        require(path, r"AttachButton\(onPick: attach\)", "botão Anexar não conectado")
        require(path, r"importFiles:.*?importAttachments.*?insertion: insertion", "importação/inserção não conectadas ao editor")
        require(path, r"insertion = MarkdownInsertion\(text: links", "botão não solicita inserção undoable")
    require(BASE + "ProjectModel.swift", r"func undoManager\(forDoc slug: String\).*?docUndoManagers\[slug\].*?docUndoManagers\[slug\] = manager", "UndoManager não é preservado por documento")
    appkit("undo")
elif RULE == "A1657562":
    no_background([EDITOR])
    for name in ["Agent", "Command", "Skill"]:
        path = BASE + name + "View.swift"
        require(path, rf'MarkdownEditor\(text: \$text, undoManager: model\.undoManager\(forDoc: "{name.lower()}:.*?autoFocus: false\)', "consumidor perdeu binding, undo próprio ou política de foco")
        body = source(path)
        if re.search(r"MarkdownEditor\([^)]*baseURL:", body):
            fail(path, "MarkdownEditor(", "editor de prompts não deve ativar renderização WYSIWYG")
    appkit("prompt")
elif RULE == "5C7F52C8":
    tests = sorted((ROOT / "Tests/VibeDeckAppTests").glob("*.swift"))
    relevant = [p for p in tests if "MarkdownHighlighter" in p.read_text()]
    if not relevant:
        fail("Tests/VibeDeckAppTests", "", "nenhum teste de unidade cobre MarkdownHighlighter, cursor ou fundo")
    coverage = "\n".join(p.read_text() for p in relevant)
    for label, pattern in [("atributos", r"attributes?\("), ("cursor", r"selectedRange|selection|cursor"),
                           ("fundo", r"backgroundColor|drawsBackground"), ("asserções", r"#expect|XCTAssert")]:
        if not re.search(pattern, coverage):
            fail(str(relevant[0].relative_to(ROOT)), "", f"cobertura ausente: {label}")
    # SwiftPM must use local dependencies; never fetch or update the network.
    with tempfile.TemporaryDirectory(prefix="vibedeck-swift-cache-") as cache:
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=cache, SWIFTPM_MODULECACHE_OVERRIDE=cache)
        run(["/usr/bin/xcrun", "swift", "test", "--disable-sandbox", "--disable-automatic-resolution", "--skip-update"], env)
else:
    fail(".vibedeck/tests/melhorar-o-md-viewer/check.py", "", f"regra desconhecida: {RULE}")
print(f"{RULE}: OK")
