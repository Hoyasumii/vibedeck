import Foundation

/// Trusted offline replacement for graphify's vis-network CDN HTML. Graph attributes remain data.
public enum GraphHTML {
    public static func render(_ graph: ProjectGraph, root: URL) throws -> Data {
        guard let scriptURL = Bundle.module.url(forResource: "graph", withExtension: "js", subdirectory: "GraphResources"),
              let styleURL = Bundle.module.url(forResource: "graph", withExtension: "css", subdirectory: "GraphResources") else {
            throw VibeDeckError.graph("Recursos locais do grafo ausentes. Reinstale o VibeDeck.")
        }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let style = try String(contentsOf: styleURL, encoding: .utf8)
        var object = graph.value.object ?? [:]
        object["nodes"] = .array(graph.nodes.map { node in
            var value = node.object ?? [:]
            value["vibedeck_source_available"] = .bool(ProjectGraph.sourceURL(node["source_file"]?.string ?? "", root: root) != nil)
            return .object(value)
        })
        object["links"] = .array(graph.links)
        // Prevent graph-controlled labels from closing an HTML script element.
        let data = String(decoding: try VDJSON.encode(JSONValue.object(object)), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        let nonce = UUID().uuidString
        let html = """
        <!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
        <meta name="vibedeck-graph-renderer" content="1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'nonce-\(nonce)'; img-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Grafo do projeto</title>
        <style nonce="\(nonce)">\(style)</style></head><body>
        <header><label for="search">Buscar nós</label><input id="search" type="search" placeholder="Nome, arquivo ou comunidade">
        <button id="overview">Visão geral</button><button id="zoom-in" aria-label="Aumentar zoom">+</button>
        <button id="zoom-out" aria-label="Diminuir zoom">−</button><button id="center">Centralizar</button></header>
        <div id="status" role="status" aria-live="polite"></div>
        <main><svg id="graph" tabindex="0" role="group" aria-label="Grafo: navegue com as setas e selecione com Enter"></svg>
        <aside><section id="details" aria-label="Inspeção do nó"></section><section id="results" aria-label="Resultados e comunidades"></section></aside></main>
        <script id="graph-data" type="application/json" nonce="\(nonce)">\(data)</script>
        <script nonce="\(nonce)">\(script)</script></body></html>
        """
        return Data(html.utf8)
    }

    public static func write(_ graph: ProjectGraph, root: URL, output: URL) throws {
        try AtomicFile.write(render(graph, root: root), to: output)
    }
}
