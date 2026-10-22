import Foundation

/// Counts reported by providers only; nil means unavailable, never zero or a character estimate.
public struct AITokenUsage: Codable, Equatable, Sendable {
    public var input: Int?
    public var output: Int?
    public var cachedInput: Int?
    public var cacheWrite: Int?
    public var reasoningOutput: Int?
    public init(input: Int? = nil, output: Int? = nil, cachedInput: Int? = nil, cacheWrite: Int? = nil, reasoningOutput: Int? = nil) {
        self.input = input; self.output = output; self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite; self.reasoningOutput = reasoningOutput
    }
    private static func count(_ value: JSONValue?) -> Int? {
        guard let n = value?.number, n.isFinite, n >= 0, n < Double(Int.max), n.rounded(.down) == n else { return nil }
        return Int(n)
    }
    public static func claude(_ value: JSONValue?) -> Self {
        // Claude reports cache categories separately from uncached input.
        let uncached = count(value?["input_tokens"])
        let cached = count(value?["cache_read_input_tokens"])
        let write = count(value?["cache_creation_input_tokens"])
        return Self(input: uncached.map { $0 + (cached ?? 0) + (write ?? 0) },
                    output: count(value?["output_tokens"]), cachedInput: cached, cacheWrite: write)
    }
    public static func codex(_ value: JSONValue?) -> Self {
        Self(input: count(value?["inputTokens"]), output: count(value?["outputTokens"]),
             cachedInput: count(value?["cachedInputTokens"]), cacheWrite: count(value?["cacheWriteInputTokens"]),
             reasoningOutput: count(value?["reasoningOutputTokens"]))
    }
    /// Codex cumulative totals -> this turn, including all tool/model rounds. Never sum cumulative events.
    public func since(_ baseline: Self) -> Self {
        func delta(_ a: Int?, _ b: Int?) -> Int? { a.map { max(0, $0 - (b ?? 0)) } }
        return Self(input: delta(input, baseline.input), output: delta(output, baseline.output),
                    cachedInput: delta(cachedInput, baseline.cachedInput), cacheWrite: delta(cacheWrite, baseline.cacheWrite),
                    reasoningOutput: delta(reasoningOutput, baseline.reasoningOutput))
    }
}

public struct AIUsageRecord: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var taskID: String
    public var operation: String
    public var provider: AIProvider
    public var model: String?
    public var startedAt = Date()
    public var duration: TimeInterval = 0
    public var attempt: Int
    public var status = "running"
    public var promptCharacters: Int
    public var tokens = AITokenUsage()
    public var costUSD: Double?
    public var coverage = "provider-reported"
    public init(taskID: String = UUID().uuidString, operation: String, provider: AIProvider, model: String? = nil,
                attempt: Int = 1, prompt: String) {
        self.taskID = taskID; self.operation = operation; self.provider = provider; self.model = model
        self.attempt = attempt; promptCharacters = prompt.count
    }
    public mutating func finish(_ status: String) { self.status = status; duration = max(0, Date().timeIntervalSince(startedAt)) }
}

public struct AIUsageTask: Identifiable, Sendable {
    public let id: String
    public let records: [AIUsageRecord]
    public var duration: TimeInterval { records.reduce(0) { $0 + $1.duration } }
    /// A partial total must not be presented as the total consumption of a task.
    public func total(_ field: KeyPath<AITokenUsage, Int?>) -> Int? {
        let values = records.compactMap { $0.tokens[keyPath: field] }
        return values.count == records.count ? values.reduce(0, +) : nil
    }
    public static func group(_ records: [AIUsageRecord]) -> [Self] {
        Dictionary(grouping: records, by: \.taskID).map { id, records in
            Self(id: id, records: records.sorted { $0.startedAt > $1.startedAt })
        }.sorted { ($0.records.first?.startedAt ?? .distantPast) > ($1.records.first?.startedAt ?? .distantPast) }
    }
}

/// One file per attempt avoids read/modify/write races between background jobs and processes.
/// Stored outside the repository alongside local chat data; no prompt text or network telemetry.
public struct AIUsageStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public init(root: URL) { directory = AILocalStore.directory(root: root).appending(path: "usage") }
    public func save(_ record: AIUsageRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(VDJSON.encode(record), to: directory.appending(path: record.id.uuidString + ".json"))
    }
    public func list() throws -> [AIUsageRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try VDJSON.decoder.decode(AIUsageRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func clear() throws {
        for record in try list() { try FileManager.default.removeItem(at: directory.appending(path: record.id.uuidString + ".json")) }
    }
}
