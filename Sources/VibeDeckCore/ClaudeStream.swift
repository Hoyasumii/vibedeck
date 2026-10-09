import Foundation
import Synchronization

// MARK: - JSON value

/// Arbitrary JSON, so tool inputs can be shown and sent back to Claude Code unchanged.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
}

// MARK: - Events (stdout)

/// Claude Code's permission modes that the panel offers.
public enum ClaudePermissionMode: String, CaseIterable, Sendable {
    /// Asks before edits and commands.
    case `default`
    /// Read-only: Claude explores and proposes a plan for approval (ExitPlanMode).
    case plan
    /// File edits go through without asking; commands still ask.
    case acceptEdits
    /// Claude Code decides on its own what is safe to run; risky actions still ask.
    case auto
}

/// Model chosen in the panel, passed as `--model`. `.automatic` leaves Claude Code's own setting.
public enum ClaudeModel: String, CaseIterable, Sendable {
    case automatic = ""
    case fable, opus, sonnet, haiku
}

/// Effort chosen in the panel, passed as `--effort`. `.automatic` leaves Claude Code's own setting.
public enum ClaudeEffort: String, CaseIterable, Sendable {
    case automatic = ""
    case low, medium, high, xhigh, max
}

public enum ClaudeLaunch {
    /// Arguments for a `claude -p` stream-json session with the panel's choices.
    public static func arguments(mode: ClaudePermissionMode, model: ClaudeModel, effort: ClaudeEffort, resume sessionId: String?) -> [String] {
        var arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--permission-prompt-tool", "stdio",
            "--permission-mode", mode.rawValue,
        ]
        if model != .automatic { arguments += ["--model", model.rawValue] }
        if effort != .automatic { arguments += ["--effort", effort.rawValue] }
        if let sessionId { arguments += ["--resume", sessionId] }
        return arguments
    }

    /// Arguments for a one-shot background `claude -p` job (rule test generation): nobody answers permission
    /// prompts, so edits go through and the tools the job needs are pre-allowed.
    public static func headlessArguments(prompt: String, model: ClaudeModel = .automatic, effort: ClaudeEffort = .automatic) -> [String] {
        var arguments = [
            "-p", prompt, "--output-format", "stream-json", "--verbose",
            "--permission-mode", ClaudePermissionMode.acceptEdits.rawValue,
            "--allowedTools", "Read Edit Write Glob Grep Bash",
        ]
        if model != .automatic { arguments += ["--model", model.rawValue] }
        if effort != .automatic { arguments += ["--effort", effort.rawValue] }
        return arguments
    }
}

/// A question asked through Claude Code's AskUserQuestion tool.
public struct ClaudeQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        public var description: String?
    }

    public var question: String
    public var header: String?
    public var options: [Option]
    public var multiSelect: Bool
}

/// `can_use_tool` control request: Claude Code asks the host to allow a tool call (or answer a question).
public struct ClaudePermissionRequest: Equatable, Sendable, Identifiable {
    public var requestId: String
    public var toolName: String
    public var input: [String: JSONValue]
    public var description: String?
    public var suggestions: [JSONValue]
    public init(requestId: String, toolName: String, input: [String: JSONValue], description: String? = nil, suggestions: [JSONValue] = []) {
        self.requestId = requestId; self.toolName = toolName; self.input = input; self.description = description; self.suggestions = suggestions
    }
    public var id: String { requestId }

    public var isQuestion: Bool { toolName == "AskUserQuestion" }

    /// ExitPlanMode: Claude finished planning and asks to approve `plan` before executing it.
    public var isPlanApproval: Bool { toolName == "ExitPlanMode" }

    public var plan: String? { input["plan"]?.string }

    public var questions: [ClaudeQuestion] {
        (input["questions"]?.array ?? []).compactMap { q in
            guard let text = q["question"]?.string else { return nil }
            let options = (q["options"]?.array ?? []).compactMap { o in
                o["label"]?.string.map { ClaudeQuestion.Option(label: $0, description: o["description"]?.string) }
            }
            return ClaudeQuestion(question: text, header: q["header"]?.string, options: options, multiSelect: q["multiSelect"]?.bool ?? false)
        }
    }
}

public struct ClaudeToolUse: Equatable, Sendable {
    public var id: String
    public var name: String
    public var input: [String: JSONValue]
}

public struct ClaudeResult: Equatable, Sendable {
    public var isError: Bool
    public var text: String?
    public var costUSD: Double?
}

/// One line of `claude -p --output-format stream-json`, reduced to what the panel shows.
/// Events from subagents (`parent_tool_use_id` set) are ignored.
public enum ClaudeEvent: Equatable, Sendable {
    case initialized(sessionId: String, model: String?, slashCommands: [String] = [])
    /// The session's permission mode changed (e.g. back to default after a plan is approved).
    case permissionModeChanged(ClaudePermissionMode)
    case textStarted
    case textDelta(String)
    case thinking
    case toolUse(ClaudeToolUse)
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case permission(ClaudePermissionRequest)
    /// A control request the panel doesn't handle; must be answered with an error so Claude doesn't hang.
    case unsupportedControl(requestId: String)
    case result(ClaudeResult)
    case ignored
}

public enum ClaudeStream {
    public static func parse(_ line: String) -> ClaudeEvent {
        guard let data = line.data(using: .utf8), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .ignored }
        if let parent = json["parent_tool_use_id"], parent != .null { return .ignored }

        switch json["type"]?.string {
        case "system":
            switch json["subtype"]?.string {
            case "init":
                guard let id = json["session_id"]?.string else { return .ignored }
                return .initialized(sessionId: id, model: json["model"]?.string, slashCommands: json["slash_commands"]?.array?.compactMap(\.string) ?? [])
            case "status":
                guard let mode = json["permissionMode"]?.string.flatMap(ClaudePermissionMode.init(rawValue:)) else { return .ignored }
                return .permissionModeChanged(mode)
            default:
                return .ignored
            }

        case "stream_event":
            let event = json["event"]
            switch event?["type"]?.string {
            case "content_block_start":
                switch event?["content_block"]?["type"]?.string {
                case "text": return .textStarted
                case "thinking": return .thinking
                default: return .ignored
                }
            case "content_block_delta":
                guard let delta = event?["delta"], delta["type"]?.string == "text_delta", let text = delta["text"]?.string else { return .ignored }
                return .textDelta(text)
            default:
                return .ignored
            }

        case "assistant":
            // Text already arrived as deltas; only tool calls are taken from the full message.
            for block in json["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_use" {
                if let id = block["id"]?.string, let name = block["name"]?.string {
                    return .toolUse(ClaudeToolUse(id: id, name: name, input: block["input"]?.object ?? [:]))
                }
            }
            return .ignored

        case "user":
            for block in json["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_result" {
                guard let id = block["tool_use_id"]?.string else { continue }
                return .toolResult(toolUseId: id, content: text(of: block["content"]), isError: block["is_error"]?.bool ?? false)
            }
            return .ignored

        case "control_request":
            guard let requestId = json["request_id"]?.string, let request = json["request"] else { return .ignored }
            guard request["subtype"]?.string == "can_use_tool", let tool = request["tool_name"]?.string else {
                return .unsupportedControl(requestId: requestId)
            }
            return .permission(ClaudePermissionRequest(
                requestId: requestId,
                toolName: tool,
                input: request["input"]?.object ?? [:],
                description: request["description"]?.string,
                suggestions: request["permission_suggestions"]?.array ?? []
            ))

        case "result":
            return .result(ClaudeResult(
                isError: json["is_error"]?.bool ?? (json["subtype"]?.string != "success"),
                text: json["result"]?.string,
                costUSD: json["total_cost_usd"]?.number
            ))

        default:
            return .ignored
        }
    }

    /// Tool result content is either a string or a list of content blocks.
    private static func text(of content: JSONValue?) -> String {
        switch content {
        case .string(let s): s
        case .array(let blocks): blocks.compactMap { $0["text"]?.string }.joined(separator: "\n")
        default: ""
        }
    }
}

// MARK: - Reading lines

/// Splits a byte stream into UTF-8 lines. Bytes after the last newline wait for the next chunk.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
        }
        return lines
    }

    /// Whatever is left when the stream ends without a trailing newline.
    public mutating func finish() -> String? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}

extension ClaudeStream {
    /// Lines read from `handle` as they arrive. `FileHandle.bytes.lines` stalls on pipes after the first
    /// line, so this uses `readabilityHandler` instead.
    public static func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let buffer = Mutex(LineBuffer())
            handle.readabilityHandler = { h in
                let data = h.availableData
                if data.isEmpty {
                    h.readabilityHandler = nil
                    if let rest = buffer.withLock({ $0.finish() }) { continuation.yield(rest) }
                    continuation.finish()
                    return
                }
                for line in buffer.withLock({ $0.append(data) }) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

// MARK: - Messages (stdin)

/// Lines written to `claude -p --input-format stream-json`.
public enum ClaudeInput {
    public enum RuleScope: String, Sendable {
        /// Until the Claude Code process ends.
        case session
        /// Saved by Claude Code in `.claude/settings.local.json`, so it also applies in the terminal.
        case localSettings
    }

    public static func userMessage(_ text: String) -> Data {
        line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": .string(text)]]]])
    }

    public static func allow(_ request: ClaudePermissionRequest, input: [String: JSONValue]? = nil, always scope: RuleScope? = nil) -> Data {
        var response: [String: JSONValue] = ["behavior": "allow", "updatedInput": .object(input ?? request.input)]
        if let scope { response["updatedPermissions"] = .array(alwaysAllowRules(for: request, scope: scope)) }
        return controlResponse(request.requestId, .object(response))
    }

    public static func deny(_ request: ClaudePermissionRequest, message: String) -> Data {
        controlResponse(request.requestId, ["behavior": "deny", "message": .string(message)])
    }

    /// Answers an AskUserQuestion call: the original input plus `answers` keyed by question text
    /// (several choices of a multi-select question are joined with ", ").
    public static func answer(_ request: ClaudePermissionRequest, _ answers: [String: [String]]) -> Data {
        var input = request.input
        input["answers"] = .object(answers.mapValues { .string($0.joined(separator: ", ")) })
        return allow(request, input: input)
    }

    /// Approves the plan of an ExitPlanMode request. With a `mode` (e.g. `.acceptEdits` or `.auto`), the
    /// session switches to it to carry out the plan; otherwise Claude Code returns to its default mode.
    public static func approvePlan(_ request: ClaudePermissionRequest, then mode: ClaudePermissionMode?) -> Data {
        var response: [String: JSONValue] = ["behavior": "allow", "updatedInput": .object(request.input)]
        if let mode {
            response["updatedPermissions"] = [["type": "setMode", "mode": .string(mode.rawValue), "destination": "session"]]
        }
        return controlResponse(request.requestId, .object(response))
    }

    /// Switches the running session's permission mode.
    public static func setPermissionMode(_ mode: ClaudePermissionMode, requestId: String = UUID().uuidString) -> Data {
        line(["type": "control_request", "request_id": .string(requestId), "request": ["subtype": "set_permission_mode", "mode": .string(mode.rawValue)]])
    }

    public static func unsupported(requestId: String) -> Data {
        line(["type": "control_response", "response": ["subtype": "error", "request_id": .string(requestId), "error": "Não suportado pelo VibeDeck"]])
    }

    public static func interrupt(requestId: String = UUID().uuidString) -> Data {
        line(["type": "control_request", "request_id": .string(requestId), "request": ["subtype": "interrupt"]])
    }

    /// Claude Code's own `addRules` suggestion when it has one (e.g. the exact Bash command), otherwise a
    /// rule for the whole tool; rescoped to `scope`.
    public static func alwaysAllowRules(for request: ClaudePermissionRequest, scope: RuleScope) -> [JSONValue] {
        let suggested = request.suggestions.compactMap { suggestion -> JSONValue? in
            guard var o = suggestion.object, o["type"]?.string == "addRules" else { return nil }
            o["destination"] = .string(scope.rawValue)
            return .object(o)
        }
        if !suggested.isEmpty { return suggested }
        return [["type": "addRules", "rules": [["toolName": .string(request.toolName)]], "behavior": "allow", "destination": .string(scope.rawValue)]]
    }

    /// Human-readable form of the rules `alwaysAllowRules` would add, e.g. `Bash(touch a.txt)`.
    public static func ruleLabels(for request: ClaudePermissionRequest, scope: RuleScope) -> [String] {
        alwaysAllowRules(for: request, scope: scope).flatMap { $0["rules"]?.array ?? [] }.compactMap { rule in
            guard let tool = rule["toolName"]?.string else { return nil }
            return rule["ruleContent"]?.string.map { "\(tool)(\($0))" } ?? tool
        }
    }

    private static func controlResponse(_ requestId: String, _ response: JSONValue) -> Data {
        line(["type": "control_response", "response": ["subtype": "success", "request_id": .string(requestId), "response": response]])
    }

    private static func line(_ value: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return ((try? encoder.encode(value)) ?? Data()) + Data("\n".utf8)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
