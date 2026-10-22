import Foundation

// Início guiado (MUD-001, decisão D3): tools `onboarding_status` e `onboarding_apply` do Core.
// `skip` e `complete` só gravam o estado (.vibedeck/onboarding.json); `import` cadastra só os itens `tipo:nome` pedidos.

/// Resposta de `onboarding_status` (camelCase, como o Core serializa).
struct OnboardingReport: Decodable, Equatable, Sendable {
    struct PatternRef: Decodable, Equatable, Identifiable, Sendable {
        var id: String
        var name: String
    }

    /// Skill, agente ou comando já presente no projeto (`.claude/{agents,commands,skills}`, `.codex/prompts`).
    struct Resource: Decodable, Equatable, Identifiable, Sendable {
        var kind: String
        var provider: String
        var name: String
        var slug: String
        var origin: String
        /// Já existe em `.vibedeck/`: aparece bloqueado e não é duplicado.
        var registered: Bool

        var id: String { kind + ":" + slug }

        var kindLabel: String {
            switch kind {
            case "agent": return "Agente"
            case "command": return "Comando"
            default: return "Skill"
            }
        }
    }

    var hasProject: Bool
    /// `pending`, `skipped` ou `done`.
    var status: String
    var persisted: Bool
    var updatedAt: String?
    var shouldPrompt: Bool
    var step: String
    var stackEmpty: Bool
    var stack: [String]
    var patterns: [PatternRef]
    var resources: [Resource]

    var isSkipped: Bool { status == "skipped" }
}

struct OnboardingOutcome: Decodable, Equatable, Sendable {
    var imported: [String]
    var alreadyRegistered: [String]
    var warnings: [String]
}

extension CoreStore {
    func onboardingStatus() async throws -> OnboardingReport {
        try await callJSON("onboarding_status", as: OnboardingReport.self, idempotent: true)
    }

    /// "Pular por agora": retomável em Projeto › Visão geral; não cria registros.
    func onboardingSkip() async throws {
        _ = try await call("onboarding_apply", ["action": "skip"])
    }

    func onboardingComplete() async throws {
        _ = try await call("onboarding_apply", ["action": "complete"])
    }

    /// Cadastra só os recursos marcados (`agent:nome`, `command:nome`, `skill:nome`). O app pede `author: human`
    /// (foi o usuário quem escolheu); se o Core ainda ignorar o argumento, o autor fica como o Core definir.
    func onboardingImport(_ items: [String]) async throws -> OnboardingOutcome {
        try await callJSON("onboarding_apply", ["action": "import", "items": items, "author": "human"], as: OnboardingOutcome.self)
    }
}
