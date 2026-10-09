import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct AIEfficiencyTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func guideReducesInitialContextWithoutLosingDocumentation() throws {
        #expect(Double(AgentsGuide.markdown.count) / Double(AgentsGuide.referenceMarkdown.count) < 0.70)
        // Read on every session: was 4,393 bytes before the 2026-10-09 cut.
        #expect(AgentsGuide.markdown.utf8.count <= 3_900)
        for contract in ["rules_for", "submit_rule_check", "passed", "verify_manual", "pending", "provider", "modelo"] {
            #expect(AgentsGuide.markdown.contains(contract))
        }
        #expect(AgentsGuide.sections.allSatisfy { AgentsGuide.referenceMarkdown.contains($0) })
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        try Data("guia antigo".utf8).write(to: store.agentsURL)
        try store.refreshAgentsGuideIfNeeded()
        #expect(try String(contentsOf: store.agentsURL, encoding: .utf8) == AgentsGuide.markdown)
        #expect(try String(contentsOf: store.dataDir.appending(path: "guide.md"), encoding: .utf8) == AgentsGuide.referenceMarkdown)
    }

    @Test func contextPagesAreLosslessImmutableAndConfined() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = AIContextStore(directory: root)
        let text = String(repeating: "Decisão: não apagar 👩🏽‍💻.\n", count: 400)
        let ref = try store.save(text, title: "Decisões")
        #expect(try store.save(text, title: "Outro título").id == ref.id)
        var recovered = "", offset = 0
        repeat {
            let page = try store.page(id: ref.id, offset: offset, limit: 73)
            recovered += page.text
            guard let next = page.nextOffset else { break }
            offset = next
        } while true
        #expect(recovered == text)
        #expect(throws: AIContextError.self) { try store.page(id: "../../secret") }
        #expect(throws: AIContextError.self) { try store.page(id: ref.id, offset: -1) }
        #expect(throws: AIContextError.self) { try store.page(id: ref.id, limit: 0) }
        #expect(throws: (any Error).self) { try store.page(id: String(repeating: "0", count: 64)) }
    }

    @Test func mentionedChatIsRecoverableAndFullModeRemainsAvailable() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = AIContextStore(directory: root)
        let chat = ClaudeChat(title: "Referência", messages: [.init(role: .user, text: String(repeating: "requisito essencial\n", count: 1000))])
        let full = ClaudeChat.wireText("tarefa", mentioning: [chat], contextStore: store, includeFullChats: true)
        let compact = ClaudeChat.wireText("tarefa", mentioning: [chat], contextStore: store)
        #expect(compact.count < full.count / 2)
        let ref = try store.save(chat.contextJSON(), title: chat.title)
        #expect(compact.contains(ref.path))
        #expect(try String(contentsOfFile: ref.path, encoding: .utf8) == chat.contextJSON())
        let invalidStore = AIContextStore(directory: URL(fileURLWithPath: ref.path))
        #expect(ClaudeChat.wireText("tarefa", mentioning: [chat], contextStore: invalidStore) == full)
    }

    @Test func catalogPaginatesWithoutSendingUserPrompts() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let secret = String(repeating: "instrução personalizada", count: 100)
        for name in ["A", "B", "C"] { try store.createAgent(title: name, summary: "Uso específico", prompt: secret) }
        let first = try store.aiCatalog(kind: "agents", limit: 2)
        #expect(first.items.count == 2 && first.nextOffset == 2 && first.total == 3)
        let last = try store.aiCatalog(kind: "agents", offset: 2, limit: 2)
        #expect(last.items.count == 1 && last.nextOffset == nil)
        #expect(!String(decoding: try VDJSON.encode(first), as: UTF8.self).contains(secret))
        #expect(try store.loadAgent("a").prompt == secret)
    }

    @Test func usageSeparatesMissingZeroCacheAndCumulativeCounts() throws {
        #expect(AITokenUsage.claude(nil).input == nil)
        let claude = AITokenUsage.claude(.object(["input_tokens": .number(10), "cache_read_input_tokens": .number(30), "cache_creation_input_tokens": .number(20), "output_tokens": .number(0)]))
        #expect(claude.input == 60 && claude.output == 0 && claude.cachedInput == 30)
        let total = AITokenUsage(input: 1200, output: 120, cachedInput: 600)
        let baseline = AITokenUsage(input: 1000, output: 100, cachedInput: 500)
        #expect(total.since(baseline) == AITokenUsage(input: 200, output: 20, cachedInput: 100))
        #expect(AITokenUsage.codex(.object(["inputTokens": .number(-1)])).input == nil)
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = AIUsageStore(directory: root)
        var a = AIUsageRecord(taskID: "task", operation: "Teste", provider: .codex, prompt: "secret prompt")
        a.tokens = total.since(baseline); a.finish("completed")
        try store.save(a); try store.save(a)
        let b = AIUsageRecord(taskID: "task", operation: "Teste", provider: .codex, attempt: 2, prompt: "outro")
        try store.save(b)
        #expect(AIUsageTask.group([a, b]).first?.total(\.input) == nil)
        #expect(AIUsageTask.group([a]).first?.total(\.input) == 200)
        #expect(try store.list().count == 2)
        #expect(!String(decoding: try VDJSON.encode(a), as: UTF8.self).contains("secret prompt"))
        try store.clear(); #expect(try store.list().isEmpty)
    }

    @Test func workflowKeepsOldDecisionsAndFullOutputs() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let command = try store.createCommand(title: "Fazer", prompt: "REQUISITO PERSONALIZADO $ARGUMENTS")
        let workflow = try store.createWorkflow(title: "Fluxo")
        try store.addWorkflowStep(to: workflow.slug, kind: .command, target: command.slug)
        let started = try store.startRun(workflow.slug, input: "entrada essencial")
        var run = try store.loadRun(started.ref)
        run.history = (0..<15).map { WorkflowRunEntry(step: "etapa-\($0)", verdict: "FALHA", summary: String(repeating: "log", count: 1000), cycle: 1) }
        var decision = WorkflowQuestion(number: 1, step: "etapa-antiga", question: "Preservar compatibilidade?")
        decision.answer = "Sim, inclusive arquivos legados"
        run.questions = [decision]
        try store.saveRun(run, ref: started.ref)
        let prompt = try store.runStepPrompt(started.ref)
        #expect(prompt.contains("REQUISITO PERSONALIZADO entrada essencial"))
        #expect(prompt.contains("Sim, inclusive arquivos legados"))
        #expect(prompt.contains("etapa-0") && prompt.contains("FALHA") && prompt.contains("run.json"))
        let output = String(repeating: "evidência\n", count: 2000) + "FALHA NO FINAL"
        let reference = try store.saveRunOutput(started.ref, output: output)
        let relative = try #require(reference.split(separator: "`").dropFirst().first)
        #expect(try String(contentsOf: root.appending(path: String(relative)), encoding: .utf8) == output)
    }

    @Test func ruleCheckSummaryKeepsEveryVerdictAndPointsToTheFullCheck() throws {
        let passing = (0..<46).map {
            RuleResult(topic: "geral", ruleId: UUID(), verdict: $0.isMultiple(of: 2) ? .pass : .na,
                       note: ".vibedeck/tests/geral/\($0).sh (exit 0)\n" + String(repeating: "saída do script ", count: 20), source: .script, exitCode: 0)
        }
        let failing = RuleResult(topic: "geral", ruleId: UUID(), verdict: .fail, note: "script.sh (exit 1)\nERRO ESSENCIAL na linha 42", source: .script, exitCode: 1)
        let check = RuleCheck(
            task: "x", files: ["Sources/A.swift"], topics: ["geral"], reviewItem: nil, results: passing + [failing],
            passed: false, warnings: ["aviso should"], failures: ["regra must quebrada", "outra must"],
            pending: (1...7).map { "manual \($0)" }, author: .ai
        )
        let summary = try check.agentSummary()
        let verbose = try check.agentSummary(verbose: true)
        // Integrity: every failure and warning, the failing script output, the pending count and the full check's path.
        for text in check.failures + check.warnings + ["ERRO ESSENCIAL na linha 42", "7 regra(s) manual(is)", check.relativePath] {
            #expect(summary.contains(text))
        }
        #expect(check.relativePath.hasPrefix(".vibedeck/checks/") && check.relativePath.hasSuffix(".json"))
        // Compatibility: verbose is the old answer, the summary followed by the whole check.
        #expect(verbose.hasPrefix(summary))
        var decoded = try VDJSON.decoder.decode(RuleCheck.self, from: Data(verbose.dropFirst(summary.count + 1).utf8))
        decoded.createdAt = check.createdAt  // ISO 8601 drops fractional seconds
        #expect(decoded == check)
        // Economy.
        #expect(Double(summary.count) <= Double(verbose.count) * 0.30)
    }

    @Test func compactRulesForKeepsEveryRuleAndResolvesItsIds() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        _ = try store.createTopic(title: "Geral", description: String(repeating: "Quando se aplica. ", count: 10), paths: ["Sources/**"])
        var manual: [Rule] = []
        for i in 0..<20 {
            let (slug, rule) = try store.addRule(Rule(text: "Regra \(i)", details: "Como verificar \(i)", severity: i.isMultiple(of: 3) ? .should : .must), toTopic: "Geral")
            if i.isMultiple(of: 4) {
                try store.setRuleTest(rule.id.uuidString, mode: .manual, reason: "julgamento")
                manual.append(rule)
            } else {
                try store.setRuleTest(rule.id.uuidString, mode: .script, command: RuleTestPrompt.scriptPath(topic: slug, rule: rule))
            }
        }
        let applicable = try store.applicableTopics(files: ["Sources/A.swift"])
        let full = String(decoding: try VDJSON.encoder.encode(applicable.map { TopicChecklist(slug: $0.slug, topic: $0.topic, includeManual: false) }), as: UTF8.self)
        let compact = try TopicChecklist.compactJSON(TopicChecklist.compact(applicable, includeManual: false))

        // Integrity: same rules, texts, severities, check modes and manual count as the full form.
        struct Row: Decodable, Equatable { let text: String; let severity: String; let check: String }
        struct Topic: Decodable { let slug: String; let rules: [Row]; let manualRules: Int? }
        let fullTopics = try JSONDecoder().decode([Topic].self, from: Data(full.utf8))
        let compactTopics = try JSONDecoder().decode([Topic].self, from: Data(compact.utf8))
        #expect(compactTopics.map(\.slug) == fullTopics.map(\.slug))
        #expect(compactTopics.map(\.rules) == fullTopics.map(\.rules))
        #expect(compactTopics.map(\.manualRules) == fullTopics.map(\.manualRules))
        #expect(compactTopics.flatMap(\.rules).count == 15)

        // The shortened ids are what submit_rule_check receives back.
        let withManual = TopicChecklist.compact(applicable, includeManual: true)
        let ids = withManual.flatMap(\.rules).filter { $0.check == "manual" }.map(\.ruleId)
        #expect(ids.count == manual.count && ids.allSatisfy { $0.count == 8 })
        let check = try store.submitCheck(task: "x", files: ["Sources/A.swift"], answers: ids.map { RuleAnswer(ruleId: $0, verdict: .pass, note: "li") },
                                          verifyManual: true, runner: RuleTestRunner { _, _ in RuleTestOutcome(exitCode: 0, output: "") })
        #expect(check.passed && check.pending.isEmpty)
        #expect(Set(check.results.filter { $0.source == .agent }.map(\.ruleId)) == Set(manual.map(\.id)))

        // Economy.
        #expect(Double(compact.count) <= Double(full.count) * 0.70)
    }

    @Test func sharedPolicyAppearsOnceInTheGuide() {
        #expect(AgentsGuide.markdown.components(separatedBy: AIPromptPolicy.instructions).count == 2)
    }
}
