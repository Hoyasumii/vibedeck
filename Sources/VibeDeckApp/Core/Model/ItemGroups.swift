import Foundation

/// Directory groups are separate from review themes (one ReviewGroup JSON per theme).
enum ItemConcept: String, Codable, CaseIterable, Sendable {
    case ideas, reviews, docs, skills
    var fileExtension: String { self == .docs ? "md" : "json" }
}

struct ItemDirectory: Codable, Equatable, Sendable, Identifiable {
    var path: String
    var id: String { path }
    init(path: String) { self.path = path }
}

struct GroupedRecord<Value: Encodable>: Encodable {
    let slug: String
    let value: Value
    init(slug: String, value: Value) { self.slug = slug; self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(CoreStore.groupPath(of: slug), forKey: .group)
    }
    private enum Keys: String, CodingKey { case slug, group }
}




struct GroupMoveReceipt: Sendable {
    struct ReferenceChange: Sendable {
        let beforeURL: URL
        let afterURL: URL
        let before: Data
        let after: Data
    }
    let concept: ItemConcept
    let source: String
    let destination: String
    let isDirectory: Bool
    let references: [ReferenceChange]
}


// Preserve the pre-grouping flow builders for callers with flat fixtures, while accepting grouped lists.
extension AgentFlow {
    static func build(kind: NextStepKind = .agent, from slug: String,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> AgentFlowNode? {
        build(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
    static func json(kind: NextStepKind = .agent, from slug: String,
                            agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                            skills: [(slug: String, skill: Skill, group: String)]) throws -> String? {
        try json(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}

extension WorkflowPlan {
    static func build(slug: String, workflow: Workflow, input: String? = nil,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> WorkflowPlan {
        build(slug: slug, workflow: workflow, input: input, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}
