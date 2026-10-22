#!/usr/bin/env python3
"""Importa o protótipo exportado do claude.ai (HTML único) para design/prototipo/.

Uso: python3 -I scripts/prototipo/extract.py "<arquivo baixado>.html" [design/prototipo]

Gera fontes editáveis: uma prancha por arquivo em boards/, componentes .dc.html em
components/, scripts em vendor/ e o carregador em bundler/loader.html. Pranchas já
existentes são sobrescritas; rode só para reimportar uma versão nova do artefato.
"""
import base64, gzip, json, os, re, sys, unicodedata

VENDOR = {
    "https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js": "react.production.min.js",
    "https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js": "react-dom.production.min.js",
}


def blocks(html):
    def block(t):
        m = re.search(r'<script type="__bundler/%s">\s*(.*?)\s*</script>' % re.escape(t), html, re.S)
        if not m:
            sys.exit(f"pacote sem o bloco {t}: o arquivo não parece um export do claude.ai")
        return json.loads(m.group(1))
    return block("manifest"), block("template"), block("ext_resources"), block("page_order")


def decode(entry):
    data = base64.b64decode(entry["data"])
    return gzip.decompress(data) if entry.get("compressed") else data


def slug(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = open(sys.argv[1], encoding="utf-8").read()
    out = sys.argv[2] if len(sys.argv) > 2 else "design/prototipo"
    for d in ("boards", "components", "vendor", "bundler"):
        os.makedirs(os.path.join(out, d), exist_ok=True)

    head = src[: src.index('<script type="__bundler/manifest">')]
    title = re.search(r"<title>(.*?)</title>", head).group(1)
    loader = head.replace(title, "{{TITLE}}")
    open(os.path.join(out, "bundler/loader.html"), "w", encoding="utf-8").write(loader)

    manifest, template, _, order = blocks(src)
    page_title = re.search(r"<title>(.*?)</title>", template).group(1)
    boards = []
    named_scripts = {}
    for i, (name, uuid, w, h) in enumerate(re.findall(
            r'<h2>(.*?)</h2><iframe src="about:blank#([0-9a-f-]+)"[^>]*width="(\d+)" height="(\d+)"', template)):
        page = decode(manifest[uuid]).decode("utf-8")
        pm, ptpl, pext, _ = blocks(page)
        ext_by_uuid = {e["uuid"]: e["id"] for e in pext}
        for au, entry in pm.items():
            data = decode(entry)
            ext_id = ext_by_uuid.get(au)
            if ext_id in VENDOR:
                fname = os.path.join("vendor", VENDOR[ext_id])
            elif ext_id:
                fname = os.path.join("components", os.path.basename(ext_id))
            else:
                # Scripts do <head>: runtime dos componentes e biblioteca VibeDeck.
                text = data[:400].decode("utf-8", "ignore")
                fname = os.path.join("vendor", "vibedeck-components.js" if "@ds-bundle" in text else "dc-runtime.js")
                ptpl = ptpl.replace(f'src="{au}"', f'src="../{fname}"')
            named_scripts[fname] = data
        fname = f"{i:02d}-{slug(name)}.html"
        open(os.path.join(out, "boards", fname), "w", encoding="utf-8").write(ptpl)
        boards.append({"file": fname, "title": name, "width": int(w), "height": int(h)})
    for fname, data in named_scripts.items():
        open(os.path.join(out, fname), "wb").write(data)
    json.dump({"title": page_title, "boards": boards}, open(os.path.join(out, "boards.json"), "w", encoding="utf-8"),
              indent=2, ensure_ascii=False)
    print(f"{len(boards)} pranchas e {len(named_scripts)} recursos em {out}")


if __name__ == "__main__":
    main()
