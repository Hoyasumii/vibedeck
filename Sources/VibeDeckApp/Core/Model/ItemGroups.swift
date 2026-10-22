import Foundation

/// Directory groups are separate from review themes (one ReviewGroup JSON per theme).
public enum ItemConcept: String, Codable, CaseIterable, Sendable {
    case ideas, reviews, docs, skills
    public var fileExtension: String { self == .docs ? "md" : "json" }
}

public struct ItemDirectory: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var id: String { path }
    public init(path: String) { self.path = path }
}

public struct GroupedRecord<Value: Encodable>: Encodable {
    public let slug: String
    public let value: Value
    public init(slug: String, value: Value) { self.slug = slug; self.value = value }
    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(CoreStore.groupPath(of: slug), forKey: .group)
    }
    private enum Keys: String, CodingKey { case slug, group }
}




public struct GroupMoveReceipt: Sendable {
    public struct ReferenceChange: Sendable {
        public let beforeURL: URL
        public let afterURL: URL
        public let before: Data
        public let after: Data
    }
    public let concept: ItemConcept
    public let source: String
    public let destination: String
    public let isDirectory: Bool
    public let references: [ReferenceChange]
}


// Preserve the pre-grouping flow builders for callers with flat fixtures, while accepting grouped lists.
extension AgentFlow {
    public static func build(kind: NextStepKind = .agent, from slug: String,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> AgentFlowNode? {
        build(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
    public static func json(kind: NextStepKind = .agent, from slug: String,
                            agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                            skills: [(slug: String, skill: Skill, group: String)]) throws -> String? {
        try json(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}

extension WorkflowPlan {
    public static func build(slug: String, workflow: Workflow, input: String? = nil,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> WorkflowPlan {
        build(slug: slug, workflow: workflow, input: input, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}
