import Foundation

// MARK: - Agent processes

/// State of one agent or subagent of a conversation, known only from provider events.
public enum AgentProcessState: String, Codable, Sendable {
    case running, succeeded, failed, interrupted
    /// Saved as running by a provider session that is gone; nothing confirmed it is still alive.
    case unconfirmed
}

/// An agent (the conversation's own, or a subagent it delegated to) seen in the provider's events.
public struct AgentProcess: Codable, Equatable, Identifiable, Sendable {
    /// Provider id: Claude's `tool_use_id` of the Agent call, Codex's thread id; `main` for the conversation's agent.
    public var id: String
    /// Other id the provider uses for it (Claude's `task_id`).
    public var alias: String?
    public var name: String
    public var detail: String?
    /// Agent that started this one, when the provider reports it.
    public var parentID: String?
    public var state: AgentProcessState
    public var startedAt: Date
    public var endedAt: Date?

    public init(id: String, alias: String? = nil, name: String, detail: String? = nil, parentID: String? = nil,
                state: AgentProcessState = .running, startedAt: Date = .now, endedAt: Date? = nil) {
        self.id = id; self.alias = alias; self.name = name; self.detail = detail; self.parentID = parentID
        self.state = state; self.startedAt = startedAt; self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey { case id, alias, name, detail, parentID, state, startedAt, endedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Agente"
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        state = (try? c.decodeIfPresent(AgentProcessState.self, forKey: .state)) ?? .unconfirmed
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(alias, forKey: .alias)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(detail, forKey: .detail)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(state, forKey: .state)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

/// Start or end of a subagent, as reported by the provider (never inferred from response text).
public enum AgentProcessEvent: Equatable, Sendable {
    /// `parentID` nil: started by the conversation's own agent.
    case started(id: String, alias: String? = nil, name: String, detail: String? = nil, parentID: String? = nil)
    /// `id` matches a process id or alias; `state` is a terminal state, or `.running` for a status update.
    case finished(id: String, state: AgentProcessState)
}

/// Processes of one conversation. Each event touches only the process it names, so simultaneous agents
/// stay running until their own end is reported.
public struct AgentProcessTracker: Equatable, Sendable {
    public static let mainID = "main"
    public private(set) var processes: [AgentProcess]

    public init(processes: [AgentProcess] = []) { self.processes = processes }

    /// Saved processes of a reopened conversation: the provider session that ran them is gone, so the ones
    /// saved as running come back unconfirmed.
    public init(restoring saved: [AgentProcess]) {
        processes = saved.map { var p = $0; if p.state == .running { p.state = .unconfirmed }; return p }
    }

    public var running: [AgentProcess] { processes.filter { $0.state == .running } }
    public var isEmpty: Bool { processes.isEmpty }

    public mutating func apply(_ event: AgentProcessEvent, now: Date = .now) {
        switch event {
        case .started(let id, let alias, let name, let detail, let parentID):
            let parent = parentID ?? (id == Self.mainID ? nil : Self.mainID)
            if let i = index(id) {
                processes[i].state = .running; processes[i].endedAt = nil
                processes[i].alias = alias ?? processes[i].alias
                if processes[i].parentID == nil { processes[i].parentID = parent }
            } else {
                processes.append(AgentProcess(id: id, alias: alias, name: name, detail: detail, parentID: parent, startedAt: now))
            }
        case .finished(let id, let state):
            guard let i = index(id) else { return }
            processes[i].state = state
            processes[i].endedAt = state == .running ? nil : now
        }
    }

    /// The conversation's own agent works from the first event of a turn until the turn's result; Claude's
    /// Agent tool calls and subagent lines arrive as `.agents`.
    public mutating func apply(_ event: AIEvent, provider: AIProvider, now: Date = .now) {
        switch event {
        case .textStarted, .textDelta, .thinking, .toolUse, .toolResult, .permission:
            startMain(provider, now: now)
        case .agents(let events):
            startMain(provider, now: now)
            for e in events { apply(e, now: now) }
        case .result(let result):
            apply(.finished(id: Self.mainID, state: result.isInterrupted ? .interrupted : result.isError ? .failed : .succeeded), now: now)
        case .initialized, .permissionModeChanged, .unsupportedControl, .ignored:
            break
        }
    }

    /// The provider process ended (stopped, interrupted or disconnected): whatever still ran in it ended too.
    /// `.unconfirmed` when only the conversation's thread was replaced and its agents can no longer be followed.
    public mutating func providerEnded(as state: AgentProcessState = .interrupted, now: Date = .now) {
        for i in processes.indices where processes[i].state == .running {
            processes[i].state = state; processes[i].endedAt = now
        }
    }

    private mutating func startMain(_ provider: AIProvider, now: Date) {
        guard processes.first(where: { $0.id == Self.mainID })?.state != .running else { return }
        if let i = index(Self.mainID) {
            processes[i].state = .running; processes[i].startedAt = now; processes[i].endedAt = nil
        } else {
            processes.insert(AgentProcess(id: Self.mainID, name: "Agente principal", detail: provider.title, startedAt: now), at: 0)
        }
    }

    private func index(_ id: String) -> Int? {
        processes.firstIndex { $0.id == id } ?? processes.firstIndex { $0.alias == id }
    }
}
