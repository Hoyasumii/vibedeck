import Foundation

/// Graphify node-link JSON. Unknown attributes survive round trips, including provenance.
public struct ProjectGraph: Sendable {
    public let value: JSONValue
    public let nodes: [JSONValue]
    public let links: [JSONValue]
    public static let maxBytes = 64 * 1024 * 1024

    public init(data: Data) throws {
        guard data.count <= Self.maxBytes else { throw VibeDeckError.graph("O grafo excede 64 MB. Gere um grafo de uma pasta menor.") }
        guard let value = try? VDJSON.decoder.decode(JSONValue.self, from: data) else {
            throw VibeDeckError.graph("JSON inválido. Gere novamente o grafo.")
        }
        guard let nodes = value["nodes"]?.array, let links = (value["links"] ?? value["edges"])?.array else {
            throw VibeDeckError.graph("Formato incompatível: esperado JSON node-link do graphify com nodes e links/edges.")
        }
        let ids = nodes.compactMap { $0["id"]?.string }
        let known = Set(ids)
        guard ids.count == nodes.count, known.count == nodes.count,
              links.allSatisfy({ known.contains($0["source"]?.string ?? "") && known.contains($0["target"]?.string ?? "") }) else {
            throw VibeDeckError.graph("Grafo inválido: IDs repetidos ou relações sem origem/destino. Gere novamente.")
        }
        self.value = value; self.nodes = nodes; self.links = links
    }

    public static func load(root: URL) throws -> ProjectGraph {
        let url = root.appending(path: "graphify-out/graph.json")
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes else {
            throw VibeDeckError.graph("O grafo excede 64 MB. Gere um grafo de uma pasta menor.")
        }
        return try ProjectGraph(data: Data(contentsOf: url))
    }

    public static func sourceURL(_ path: String, root: URL) -> URL? {
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appending(path: path))
            .standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/"),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return url
    }

    public func merging(_ semantic: JSONValue) throws -> ProjectGraph {
        guard let extraNodes = semantic["nodes"]?.array, let extraLinks = semantic["links"]?.array else {
            throw VibeDeckError.graph("A IA respondeu sem nós e relações. Tente novamente.")
        }
        var object = value.object ?? [:]
        var existing = Set(nodes.compactMap { $0["id"]?.string })
        var merged = nodes
        for node in extraNodes {
            guard let id = node["id"]?.string, existing.insert(id).inserted else {
                throw VibeDeckError.graph("A IA retornou IDs duplicados. Tente novamente.")
            }
            merged.append(node)
        }
        object["nodes"] = .array(merged)
        object["links"] = .array(links + extraLinks)
        object.removeValue(forKey: "edges")
        return try ProjectGraph(data: VDJSON.encode(JSONValue.object(object)))
    }

    public var summary: JSONValue {
        .object(["nodes": .number(Double(nodes.count)), "links": .number(Double(links.count)),
                 "generatedAt": value["vibedeck_generated_at"] ?? .null,
                 "provider": value["vibedeck_provider"] ?? .null])
    }
}
