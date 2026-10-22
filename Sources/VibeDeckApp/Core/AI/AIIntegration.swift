import Foundation

enum AIIntegrationError: LocalizedError, Sendable {
    case unavailable(AIProvider), disconnected(AIProvider)
    case modelUnavailable(String, AIProvider), effortUnavailable(String, String)
    case invalidPlan, invalidTransition
    var errorDescription: String? {
        switch self {
        case .unavailable(let provider): "\(provider.title) não está instalado."
        case .disconnected(let provider): "\(provider.title) encerrou a conexão. Retome a conversa para tentar novamente."
        case .modelUnavailable(let model, let provider): "Modelo \(model) indisponível no \(provider.title). Escolha outro modelo explicitamente."
        case .effortUnavailable(let effort, let model): "Esforço \(effort) indisponível para \(model). Escolha outro esforço explicitamente."
        case .invalidPlan: "O plano recebido está incompleto. Peça um novo plano antes de executar."
        case .invalidTransition: "A IA retornou uma transição inválida. A execução permanece na etapa atual."
        }
    }
}

enum AIFeature: String, CaseIterable, Sendable {
    case chat, planning, questions, workflows, discover, documents, graphAnalysis, ruleVerification, testGeneration
    case agents, commands, skills, mcp, rulesHook, compact, usage, claudeCollection
}
enum AIFeatureSupport: Equatable, Sendable {
    case native, equivalent, unavailable(String)
    var isAvailable: Bool { if case .unavailable = self { false } else { true } }
}
struct AIProviderCapabilities: Sendable {
    let provider: AIProvider
    init(provider: AIProvider) { self.provider = provider }
    var permissionModes: [ClaudePermissionMode] {
        provider == .claude ? ClaudePermissionMode.allCases : [.plan, .default]
    }
    func title(for mode: ClaudePermissionMode) -> String {
        switch mode {
        case .plan: "Planejar"
        case .default: provider == .codex ? "Editar projeto" : "Normal"
        case .acceptEdits: "Aceitar edições"
        case .auto: "Auto"
        }
    }
    func support(for feature: AIFeature) -> AIFeatureSupport {
        if feature == .claudeCollection, provider != .claude { return .unavailable("A coleção contém links de artefatos e documentos do Claude.") }
        if [.workflows, .agents, .commands].contains(feature) { return .equivalent }
        if feature == .planning, provider == .codex { return .equivalent }
        return .native
    }
}
extension AIProvider {
    var capabilities: AIProviderCapabilities { .init(provider: self) }
}

enum AISettingsResolver {
    /// A legacy model remains an explicit choice; incompatible choices are never replaced.
    static func resolve(provider: AIProvider, resource: AIProviderSettings? = nil, legacyModel: String? = nil,
                               session: AIProviderSettings = .init(), availableModels: [String]? = nil,
                               supportedEfforts: [String]? = nil) throws -> AIProviderSettings {
        let result = AIProviderSettings(model: resource?.model ?? legacyModel ?? session.model,
                                        effort: resource?.effort ?? session.effort)
        if let model = result.model, let availableModels, !availableModels.contains(model) {
            throw AIIntegrationError.modelUnavailable(model, provider)
        }
        if let effort = result.effort, let supportedEfforts, !supportedEfforts.contains(effort) {
            throw AIIntegrationError.effortUnavailable(effort, result.model ?? provider.title)
        }
        return result
    }
}

enum AIPlan {
    static let instructions = "Em modo de planejamento, não execute alterações. Quando o plano estiver completo, apresente-o dentro de <proposed_plan> e </proposed_plan>. Aguarde aprovação explícita do usuário antes de executar."
    static func extract(_ text: String) -> String? {
        guard let start = text.range(of: "<proposed_plan>"),
              let end = text.range(of: "</proposed_plan>", range: start.upperBound..<text.endIndex) else { return nil }
        let plan = text[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return plan.isEmpty ? nil : plan
    }
    static func request(_ text: String, id: String) -> AIPermissionRequest? {
        extract(text).map { .init(requestId: id, toolName: "ExitPlanMode", input: ["plan": .string($0)]) }
    }
}

enum AIPermissionDecision: Equatable, Sendable {
    case allowOnce, allowSession, allowAlways, deny
}
