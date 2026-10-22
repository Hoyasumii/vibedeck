#!/usr/bin/env python3
"""Empacota design/prototipo/ num HTML único, no formato dos artefatos do claude.ai.

Uso: python3 -I scripts/prototipo/build.py [design/prototipo] [saída.html] [--only <trecho do arquivo>]

A saída padrão é design/prototipo/dist/VibeDeck — Protótipo.html. Abre direto no
navegador (file://) e pode ser enviada de volta ao claude.ai. A ordem e o tamanho das
pranchas vêm de boards.json.
"""
import base64, gzip, json, os, re, sys, uuid

NS = uuid.UUID("6f1b2c1e-3c55-4a8e-9f3d-56a1d0b7c201")
VENDOR_IDS = {
    "react.production.min.js": "https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js",
    "react-dom.production.min.js": "https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js",
}
SCRIPT_SRC = re.compile(r'<script src="\.\./(vendor/[^"]+)"></script>')
COMPONENT_REF = re.compile(r'<dc-import name="([A-Za-z0-9]+)"|\./([A-Za-z0-9]+)\.dc\.html')


def uid(*parts):
    return str(uuid.uuid5(NS, "/".join(parts)))


def entry(data, mime):
    return {"mime": mime, "compressed": True,
            "data": base64.b64encode(gzip.compress(data, mtime=0)).decode()}


def js(value):
    return json.dumps(value, ensure_ascii=False).replace("</", "<\\u002F")


def document(loader, title, manifest, ext, order, template):
    return (loader.replace("{{TITLE}}", title)
            + '<script type="__bundler/manifest">\n' + json.dumps(manifest) + "\n  </script>\n\n"
            + '  <script type="__bundler/ext_resources">\n' + json.dumps(ext) + "\n  </script>\n\n"
            + '  <script type="__bundler/page_order">\n' + json.dumps(order) + "\n  </script>\n\n"
            + '  <script type="__bundler/template">\n' + js(template) + "\n  </script>\n</body>\n</html>\n")


def components_for(text, root, seen):
    for m in COMPONENT_REF.finditer(text):
        name = (m.group(1) or m.group(2)) + ".dc.html"
        if name in seen:
            continue
        path = os.path.join(root, "components", name)
        if not os.path.exists(path):
            sys.exit(f"componente não encontrado: components/{name}")
        seen.add(name)
        components_for(open(path, encoding="utf-8").read(), root, seen)
    return seen


def build_board(root, loader, board):
    name = board["file"]
    text = open(os.path.join(root, "boards", name), encoding="utf-8").read()
    title = re.search(r"<title>(.*?)</title>", text)
    title = title.group(1) if title else board["title"]
    manifest, ext = {}, []

    def script(m):
        rel = m.group(1)
        u = uid(name, rel)
        manifest[u] = entry(open(os.path.join(root, rel), "rb").read(), "text/javascript")
        return f'<script src="{u}"></script>'

    text = SCRIPT_SRC.sub(script, text)
    for comp in sorted(components_for(text, root, set())):
        u = uid(name, comp)
        manifest[u] = entry(open(os.path.join(root, "components", comp), "rb").read(), "text/html")
        ext.append({"id": f"./{comp}", "uuid": u})
    for fname, ext_id in VENDOR_IDS.items():
        u = uid(name, fname)
        manifest[u] = entry(open(os.path.join(root, "vendor", fname), "rb").read(), "text/javascript")
        ext.append({"id": ext_id, "uuid": u})
    return document(loader, title, manifest, ext, [], text)


def main():
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        i = args.index("--only")
        only = args[i + 1]
        del args[i:i + 2]
    root = args[0] if args else "design/prototipo"
    spec = json.load(open(os.path.join(root, "boards.json"), encoding="utf-8"))
    if only:
        spec["boards"] = [b for b in spec["boards"] if only in b["file"]]
        if not spec["boards"]:
            sys.exit(f"nenhuma prancha contém {only!r}")
    out = args[1] if len(args) > 1 else os.path.join(root, "dist", f"{spec['title']}.html")
    loader = open(os.path.join(root, "bundler/loader.html"), encoding="utf-8").read()
    manifest, order, sections = {}, [], []
    for board in spec["boards"]:
        u = uid("board", board["file"])
        manifest[u] = entry(build_board(root, loader, board).encode("utf-8"), "text/html")
        order.append(u)
        w, h, t = board["width"], board["height"], board["title"]
        note = f'<p class="note">{board["note"]}</p>' if board.get("note") else ""
        sections.append(
            f'<section class="board"><h2>{t}</h2>{note}<iframe src="about:blank#{u}" title="{t}" width="{w}" '
            f'height="{h}" loading="eager" style="width:{w}px;height:{h}px"></iframe></section>')
    template = ("<!DOCTYPE html>\n<html lang=\"pt-BR\"><head>\n<meta charset=\"utf-8\">\n"
                "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                f"<title>{spec['title']}</title>\n<style>\n"
                "html{background:#f5f4ef;color:#1f1e1d;font:14px/1.4 system-ui,-apple-system,\"Segoe UI\",sans-serif}\n"
                "body{margin:0;padding:48px;display:flex;flex-direction:column;align-items:flex-start;gap:48px}\n"
                ".board h2{margin:0 0 12px;font-size:13px;font-weight:500;color:#6b6a68}\n"
                ".board .note{margin:-6px 0 12px;max-width:1440px;font-size:12px;color:#8a8780}\n"
                ".board iframe{display:block;border:0;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.12)}\n"
                "</style>\n</head>\n<body>\n" + "\n".join(sections) + "\n</body></html>")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(document(loader, spec["title"], manifest, [], order, template))
    print(f"{len(order)} pranchas → {out} ({os.path.getsize(out) // 1024} KB)")


if __name__ == "__main__":
    main()
