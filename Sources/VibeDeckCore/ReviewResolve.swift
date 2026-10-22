import Foundation

/// "Resolver" in review items: the AI asks questions and proposes a plan with read-only tools, the user accepts
/// it, and only then the AI may write. This file holds what doesn't depend on the UI: which items take part,
/// the prompts, the validated plan, the one-item-at-a-time loop and the check that lets an item reach `done`.
/// Nothing here removes an item or writes `wontfix`.
public enum ReviewResolve {
    /// Read-only phase: same tools as `ReviewDiscover`.
    public static let planTools = ReviewDiscover.tools
    /// Questions the AI may ask before it must deliver a plan (one round; the next answer has to be a plan).
    public static let maxQuestions = 5

    /// Only `open` and `in_progress` items go to the AI; `done` and `wontfix` are never sent or touched.
    public static func eligible(_ items: [ReviewItem]) -> [ReviewItem] {
        items.filter { $0.status == .open || $0.status == .inProgress }
    }

    public struct Plan: Decodable, Equatable, Sendable {
        public var summary: String
        public var steps: [String]
        /// Project-relative paths the AI expects to change; they scope the check.
        public var files: [String]
    }

    public struct Question: Equatable, Identifiable, Sendable {
        public var id: Int
        public var text: String
    }

    public enum Reply: Equatable, Sendable {
        case questions([Question])
        case plan(Plan)
    }

    public struct Answered: Equatable, Sendable {
        public var question: String
        public var answer: String
        public init(question: String, answer: String) { self.question = question; self.answer = answer }
    }

    public static let schema = #"""
    {"type":"object","properties":{"questions":{"type":"array","items":{"type":"string"}},"summary":{"type":"string"},"steps":{"type":"array","items":{"type":"string"}},"files":{"type":"array","items":{"type":"string"}}},"required":["questions","summary","steps","files"]}
    """#

    private struct Raw: Decodable {
        var questions: [String]?
        var summary: String?
        var steps: [String]?
        var files: [String]?
    }

    /// Validates the AI answer. With questions it is a `.questions` reply (only when `allowQuestions`); otherwise
    /// it needs a summary and at least one step. Malformed JSON, empty fields and paths outside the project throw
    /// `discoverInvalidAnswer` without side effects.
    public static func parse(_ data: Data, allowQuestions: Bool) throws -> Reply {
        guard let raw = try? VDJSON.decoder.decode(Raw.self, from: data) else { throw VibeDeckError.discoverInvalidAnswer }
        let questions = (raw.questions ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !questions.isEmpty {
            guard allowQuestions, !questions.contains(where: \.isEmpty), questions.count <= maxQuestions else {
                throw VibeDeckError.discoverInvalidAnswer
            }
            return .questions(questions.enumerated().map { Question(id: $0.offset, text: $0.element) })
        }
        let summary = (raw.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = (raw.steps ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let files = (raw.files ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !summary.isEmpty, !steps.isEmpty, !steps.contains(where: \.isEmpty),
              !files.contains(where: { !isProjectRelative($0) }) else { throw VibeDeckError.discoverInvalidAnswer }
        return .plan(Plan(summary: summary, steps: steps, files: files))
    }

    static func isProjectRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("~") && !path.split(separator: "/").contains("..")
    }

    // MARK: Prompts

    private static func itemLines(_ item: ReviewItem, kind: String) -> [String] {
        var lines = ["Título: \(item.title)", "Tipo: \(kind)", "Prioridade: \(item.priority.label)"]
        if let details = item.details, !details.isEmpty { lines.append("Detalhes: \(details)") }
        let target = [("arquivo", item.target?.file), ("rota", item.target?.route),
                      ("componente", item.target?.component), ("seletor", item.target?.selector)]
            .compactMap { name, value in value.map { "\(name) = \($0)" } }
        if !target.isEmpty { lines.append("Onde: " + target.joined(separator: "; ")) }
        return lines
    }

    /// Planning prompt. Without `answers` the AI may ask questions; with them it must deliver the plan.
    public static func planPrompt(item: ReviewItem, kind: String, answers: [Answered] = []) -> String {
        var lines = [
            "Você vai planejar a resolução de um item de revisão do VibeDeck neste repositório (o diretório atual).",
            "Use só leitura e busca. Não altere nada nesta etapa.",
            "", "## Item",
        ] + itemLines(item, kind: kind)
        if !answers.isEmpty {
            lines += ["", "## Respostas do usuário"]
            for pair in answers { lines.append("- \(pair.question) → \(pair.answer)") }
        }
        lines += ["", "## Resposta"]
        if answers.isEmpty {
            lines.append("- questions: perguntas que você realmente precisa que o usuário responda (no máximo \(maxQuestions)); vazio se não houver dúvida. Com perguntas, deixe summary vazio e steps/files vazios.")
        } else {
            lines.append("- questions: deve ficar vazio; entregue o plano.")
        }
        lines += [
            "- summary: o que será feito, em uma ou duas frases.",
            "- steps: passos concretos e curtos, na ordem.",
            "- files: caminhos relativos à raiz dos arquivos que você espera alterar (sem .., sem caminho absoluto).",
            "Escreva tudo em português do Brasil.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Execution prompt, sent only after the user accepted `plan`.
    public static func executionPrompt(item: ReviewItem, kind: String, plan: Plan, answers: [Answered] = []) -> String {
        var lines = [
            "Resolva o item de revisão abaixo neste repositório (o diretório atual), seguindo o plano aceito pelo usuário.",
            "", "## Item",
        ] + itemLines(item, kind: kind)
        if !answers.isEmpty {
            lines += ["", "## Respostas do usuário"]
            for pair in answers { lines.append("- \(pair.question) → \(pair.answer)") }
        }
        lines += ["", "## Plano aceito", plan.summary]
        for (index, step) in plan.steps.enumerated() { lines.append("\(index + 1). \(step)") }
        if !plan.files.isEmpty { lines.append("Arquivos previstos: " + plan.files.joined(separator: ", ")) }
        lines += [
            "", "## Verificação",
            "- Use rules_for e submit_rule_check no MCP vibedeck com review_item=\(item.id.uuidString) e os arquivos realmente alterados; sem MCP, use os equivalentes vibedeck rules for/check --item \(item.id.uuidString).",
            "- No Codex, rode os scripts pelo MCP do VibeDeck, fora do terminal do agente, sem alterar o sandbox nem dispensar checks.",
            "- Para concluir o item, confira também as regras manuais must: include_manual=true, depois verify_manual=true com evidência para cada manual. Não aprove sem verificar.",
            "", "## Limites",
            "- Altere apenas arquivos dentro do diretório atual e só o que o plano pede.",
            "- Não edite .vibedeck/reviews nem o status do item: o app muda o status depois do check.",
            "- Não apague o item nem o marque como não fazer.",
            "- Se não conseguir resolver, explique o motivo e pare; não force.",
            "Escreva em português do Brasil.",
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: Group loop

    public enum Outcome: Equatable, Sendable {
        case resolved
        case failed(String)
        case cancelled
        /// Never attempted: the run was cancelled before reaching it.
        case skipped
    }

    /// Items one at a time. A failure (thrown error or `.failed`) doesn't stop the next ones nor undo finished
    /// ones; cancellation stops the loop and leaves the remaining items `.skipped`.
    public static func resolveSequentially(
        _ items: [ReviewItem], attempt: (ReviewItem) async throws -> Outcome
    ) async -> [(id: ReviewItem.ID, outcome: Outcome)] {
        var results: [(id: ReviewItem.ID, outcome: Outcome)] = []
        var stopped = false
        for item in items {
            if stopped || Task.isCancelled { results.append((item.id, .skipped)); stopped = true; continue }
            do {
                let outcome = try await attempt(item)
                results.append((item.id, outcome))
                if outcome == .cancelled { stopped = true }
            } catch is CancellationError {
                results.append((item.id, .cancelled)); stopped = true
            } catch {
                results.append((item.id, .failed(error.localizedDescription)))
            }
        }
        return results
    }

    // MARK: Check

    /// Runs the item's scripts again, retaining manual evidence recorded during this execution only.
    /// Empty result = `ensureVerified` accepts the item and the caller may mark it `done`.
    public static func verify(
        store: ProjectStore, item: ReviewItem, files: [String], verifiedSince: Date? = nil, runner: RuleTestRunner = .live
    ) -> [String] {
        do {
            let recent = try store.listChecks().first { $0.reviewItem == item.id }
            let evidence: RuleCheck?
            if let verifiedSince, let recent, recent.createdAt >= verifiedSince { evidence = recent }
            else { evidence = nil }
            let checkedFiles = Array(Set(files + (evidence?.files ?? []))).sorted()
            let topics = try store.applicableTopics(files: checkedFiles + [item.target?.file].compactMap { $0 }, explicit: item.rules)
            let manualIDs = Set(topics.flatMap { $0.topic.rules }.filter { $0.testState.needsAgent }.map(\.id))
            let answers = (evidence?.results ?? []).filter { $0.source == .agent && manualIDs.contains($0.ruleId) }
                .map { RuleAnswer(ruleId: $0.ruleId.uuidString, verdict: $0.verdict, note: $0.note) }
            let check = try store.submitCheck(task: "Resolver: \(item.title)", files: checkedFiles, reviewItem: item.id.uuidString,
                                              answers: answers, runner: runner)
            guard check.passed else { return check.failures.map { "Falhou no check: \($0)" } }
            try store.ensureVerified(item.id.uuidString)
            return []
        } catch let error as VibeDeckError {
            if case .rulesNotVerified(let problems) = error { return problems }
            return [error.localizedDescription]
        } catch {
            return [error.localizedDescription]
        }
    }
}
