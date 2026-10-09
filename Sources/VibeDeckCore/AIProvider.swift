import Foundation

public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex
    public var title: String { self == .claude ? "Claude" : "Codex" }
    public var executable: URL? { self == .claude ? ClaudeCode.executable : CodexCode.executable }
    public var isInstalled: Bool { executable != nil }
    public static var installed: [AIProvider] { allCases.filter(\.isInstalled) }
}

public struct AIProviderSettings: Codable, Equatable, Sendable {
    public var model: String?
    public var effort: String?
    public init(model: String? = nil, effort: String? = nil) { self.model = model; self.effort = effort }
}

public enum CodexCode {
    public static let executable: URL? = locate()
    public static var isInstalled: Bool { executable != nil }
    static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       path: String? = ProcessInfo.processInfo.environment["PATH"],
                       isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                       loginShellLookup: () -> String? = { ClaudeCode.loginShell("command -v codex") }) -> URL? {
        let dirs = ClaudeCode.candidateDirectories(home: home, path: path) + [home.appending(path: ".npm-global/bin").path, home.appending(path: ".cargo/bin").path]
        for dir in dirs {
            let file = URL(fileURLWithPath: dir).appending(path: "codex")
            if isExecutable(file.path) { return file }
        }
        if let file = loginShellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines), file.hasPrefix("/"), isExecutable(file) { return URL(fileURLWithPath: file) }
        return nil
    }
}

public struct CodexModel: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var efforts: [String]
    public var isDefault: Bool
    public static func list(_ response: JSONValue) -> [CodexModel] {
        (response["data"]?.array ?? []).compactMap {
            guard let model = $0["model"]?.string, $0["hidden"]?.bool != true else { return nil }
            return CodexModel(id: model, title: $0["displayName"]?.string ?? model,
                              efforts: $0["supportedReasoningEfforts"]?.array?.compactMap { $0["reasoningEffort"]?.string } ?? [],
                              isDefault: $0["isDefault"]?.bool ?? false)
        }
    }
}

public struct CodexSkill: Equatable, Sendable {
    public var name: String
    public var description: String
    public var path: String
    public static func list(_ response: JSONValue) -> [CodexSkill] {
        (response["data"]?.array ?? []).flatMap { $0["skills"]?.array ?? [] }.compactMap {
            guard $0["enabled"]?.bool != false, let name = $0["name"]?.string, let path = $0["path"]?.string else { return nil }
            return CodexSkill(name: name, description: $0["description"]?.string ?? "", path: path)
        }
    }
}

public struct CodexRateLimit: Equatable, Sendable, Identifiable {
    public var id: String
    public var usedPercent: Double
    public var minutes: Double
    public var resetsAt: Date?
    public static func list(_ response: JSONValue) -> [CodexRateLimit] {
        let buckets = response["rateLimitsByLimitId"]?.object ?? ["codex": response["rateLimits"] ?? .null]
        return buckets.keys.sorted().flatMap { key in
            ["primary", "secondary"].compactMap { window in
                guard let value = buckets[key]?[window], let used = value["usedPercent"]?.number else { return nil }
                return CodexRateLimit(id: "\(key) · \(window)", usedPercent: used, minutes: value["windowDurationMins"]?.number ?? 0,
                                      resetsAt: value["resetsAt"]?.number.map { Date(timeIntervalSince1970: $0) })
            }
        }
    }
}

public enum CodexQueries {
    @MainActor public static func limits(root: URL) async throws -> JSONValue {
        let rpc = CodexRPC(); defer { rpc.stop() }
        try await rpc.start(root: root)
        return try await rpc.request("account/rateLimits/read")
    }
}
