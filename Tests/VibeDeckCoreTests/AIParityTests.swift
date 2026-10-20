import Foundation
import Testing
@testable import VibeDeckCore

@Suite @MainActor struct AIParityTests {
    private func store() throws -> ProjectStore {
        try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "vd-parity-\(UUID().uuidString)"))
    }
    @Test(arguments: AIProvider.allCases) func capabilitiesAndExplicitSettings(provider: AIProvider) throws {
        for feature in AIFeature.allCases where feature != .claudeCollection {
            #expect(provider.capabilities.support(for: feature).isAvailable)
        }
        let resource = AIProviderSettings(model: "selected", effort: "high")
        let resolved = try AISettingsResolver.resolve(provider: provider, resource: resource, legacyModel: "legacy",
            session: .init(model: "session", effort: "low"), availableModels: ["selected"], supportedEfforts: ["high"])
        #expect(resolved == resource)
        #expect(throws: AIIntegrationError.self) {
            try AISettingsResolver.resolve(provider: provider, resource: resource, session: .init(model: "session"), availableModels: ["session"])
        }
        #expect(throws: AIIntegrationError.self) {
            try AISettingsResolver.resolve(provider: provider, resource: resource, supportedEfforts: ["low"])
        }
        #expect(try AISettingsResolver.resolve(provider: provider, session: .init()) == .init())
    }
    @Test func permissionsAndPlansAreHonest() {
        #expect(AIProvider.codex.capabilities.permissionModes == [.plan, .default])
        #expect(AIProvider.codex.capabilities.title(for: .default) == "Editar projeto")
        #expect(!AIProvider.codex.capabilities.support(for: .claudeCollection).isAvailable)
        #expect(AIPlan.extract("<proposed_plan>Incomplete") == nil)
        #expect(AIPlan.extract("<proposed_plan>  </proposed_plan>") == nil)
        let request = AIPlan.request("Antes\n<proposed_plan>Faça A, depois B.</proposed_plan>", id: "plan")
        #expect(request?.isPlanApproval == true && request?.plan == "Faça A, depois B.")
    }
    @Test func codexStreamPreservesMultipleMessagesWithoutDuplicates() {
        var stream = CodexEventStream()
        func delta(_ id: String, _ text: String) -> JSONValue { .object(["itemId": .string(id), "delta": .string(text)]) }
        func completed(_ id: String, _ text: String) -> JSONValue { .object(["item": .object(["id": .string(id), "type": .string("agentMessage"), "text": .string(text)])]) }
        #expect(stream.event("item/agentMessage/delta", delta("a", "Olá")) == .textDelta("Olá"))
        #expect(stream.event("item/completed", completed("a", "Olá")) == .ignored)
        #expect(stream.event("item/completed", completed("b", "Resposta final")) == .textDelta("Resposta final"))
        #expect(stream.event("item/completed", completed("b", "Resposta final")) == .ignored)
        #expect(stream.event("item/agentMessage/delta", delta("b", "atrasado")) == .ignored)
        let event = CodexProtocol.event("turn/completed", .object(["turn": .object(["status": .string("interrupted")])]))
        if case .result(let result) = event { #expect(result.isInterrupted) } else { Issue.record("Interrupção perdida") }
    }
    @Test func sameQuestionTextKeepsDistinctAnswers() throws {
        let params: JSONValue = .object(["questions": .array(["first", "second"].map {
            .object(["id": .string($0), "question": .string("Continuar?"), "options": .array([])])
        })])
        let request = try #require(CodexProtocol.permission(id: .number(9), method: "item/tool/requestUserInput", params: params))
        #expect(request.questions.map(\.id) == ["first", "second"])
        let answer = CodexProtocol.answer(params: params, answers: ["first": ["Sim"], "second": ["Não"]])
        #expect(answer["answers"]?["first"]?["answers"]?.array == [.string("Sim")])
        #expect(answer["answers"]?["second"]?["answers"]?.array == [.string("Não")])
    }
    @Test(arguments: AIProvider.allCases) func workflowQuestionsAndExplicitResume(provider: AIProvider) async throws {
        let store = try store(); defer { try? FileManager.default.removeItem(at: store.root) }
        _ = try store.createCommand(title: "Primeira", prompt: "Faça A")
        _ = try store.createCommand(title: "Segunda", prompt: "Faça B")
        _ = try store.createWorkflow(title: "Fluxo")
        try store.addWorkflowStep(to: "fluxo", kind: .command, target: "primeira")
        try store.addWorkflowStep(to: "fluxo", kind: .command, target: "segunda")
        try store.addWorkflowTransition("fluxo", from: "primeira", to: "segunda")
        let (ref, _, _) = try store.startRun("fluxo", input: "Teste", provider: provider)
        var steps = 0
        let waiting = try await AIWorkflowRunner.run(ref: ref, store: store, settings: { _ in .init() }, execute: { _, _, _ in
            steps += 1
            if steps == 2 {
                _ = try store.askRun(ref, questions: [.init(question: "Continuar?")])
                return "Parou\nPERGUNTA"
            }
            return "Feito\nOK"
        }, decide: { _, _ in Issue.record("Fallback não exige IA"); return nil })
        #expect(waiting.action == .ask)
        #expect(try store.loadRun(ref).history.map(\.step) == ["primeira"])
        _ = try store.stopRun(ref, reason: "Interrompido")
        let resumed = try store.resumeRun(ref)
        #expect(resumed.current == "segunda" && resumed.cycle == 1 && resumed.provider == provider)
        _ = try store.answerRun(ref, number: try #require(resumed.openQuestions.first?.number), answer: "Sim")
        let end = try await AIWorkflowRunner.run(ref: ref, store: store, settings: { _ in .init() }, execute: { prompt, _, _ in
            #expect(prompt.contains("Sim")); steps += 1; return "Concluído\nOK"
        }, decide: { _, _ in nil })
        #expect(end.action == .done && steps == 3)
        #expect(try store.loadRun(ref).history.map(\.step) == ["primeira", "segunda"])
    }
    @Test(arguments: AIProvider.allCases) func completedStepIsNotRepeatedAfterTransitionFailure(provider: AIProvider) async throws {
        let store = try store(); defer { try? FileManager.default.removeItem(at: store.root) }
        for name in ["A", "B"] { _ = try store.createCommand(title: name, prompt: name) }
        _ = try store.createWorkflow(title: "Fluxo")
        for name in ["a", "b"] { try store.addWorkflowStep(to: "fluxo", kind: .command, target: name) }
        try store.addWorkflowTransition("fluxo", from: "a", to: "b", when: "A saída atende ao requisito")
        let (ref, _, _) = try store.startRun("fluxo", input: "Teste", provider: provider)
        var executions = 0
        do {
            _ = try await AIWorkflowRunner.run(ref: ref, store: store, settings: { _ in .init() }, execute: { _, _, _ in
                executions += 1; return "Evidência\nOK"
            }, decide: { _, _ in "destino-inexistente" })
            Issue.record("Transição inválida aceita")
        } catch { #expect(error is AIIntegrationError) }
        let checkpoint = try #require(store.loadRun(ref).checkpoint)
        #expect(checkpoint.completed && checkpoint.step == "a")
        let end = try await AIWorkflowRunner.run(ref: ref, store: store, settings: { _ in .init() }, execute: { _, _, _ in
            executions += 1; return "Feito\nOK"
        }, decide: { evidence, _ in #expect(evidence == checkpoint.output); return "b" })
        #expect(end.action == .done && executions == 2)
        #expect(try store.loadRun(ref).checkpoint == nil)
    }
    @Test func pendingPlanSurvivesReopeningWithoutChangingLegacyChats() throws {
        var chat = ClaudeChat(title: "Plano", provider: .codex)
        chat.pendingPlan = "Execute A"
        let restored = try VDJSON.decoder.decode(ClaudeChat.self, from: VDJSON.encode(chat))
        #expect(restored.pendingPlan == "Execute A" && restored.provider == .codex)
        let legacy = try VDJSON.decoder.decode(ClaudeChat.self, from: Data(#"{"title":"Antiga"}"#.utf8))
        #expect(legacy.pendingPlan == nil && legacy.provider == .claude)
    }
    @Test(arguments: AIProvider.allCases) func liveProviderSmokeWhenRequested(provider: AIProvider) async throws {
        guard ProcessInfo.processInfo.environment["VIBEDECK_AI_PARITY_SMOKE"] == "1" else { return }
        let store = try store(); defer { try? FileManager.default.removeItem(at: store.root) }
        let transport: any AIConversationTransport = provider == .claude ? ClaudeConversationTransport() : CodexConversationTransport()
        defer { transport.stop() }
        var output = "", result: AIResult?, disconnected: String?
        transport.onEvent = { event in
            if case .textDelta(let delta) = event { output += delta }
            if case .result(let value) = event { result = value }
        }
        transport.onDisconnect = { disconnected = $0 }
        var config = AIConversationConfiguration(root: store.root, mode: .plan,
            instructions: "Use somente leitura. Não execute ferramentas. Responda exatamente VIBEDECK_PARITY_OK.")
        config.sessionID = try await transport.prepare(config)
        _ = try await transport.send("Responda exatamente VIBEDECK_PARITY_OK, sem ferramentas.", configuration: config, schema: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while result == nil && disconnected == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let finished = try #require(result, "\(provider.title): \(disconnected ?? "timeout")")
        #expect(!finished.isError && !finished.isInterrupted)
        #expect((output.isEmpty ? finished.text ?? "" : output).contains("VIBEDECK_PARITY_OK"))
    }
    @Test func codexApprovalScopesMatchOfferedDecisions() throws {
        let limited: JSONValue = .object(["availableDecisions": .array([.string("accept"), .string("decline")])])
        #expect(CodexProtocol.decisions(method: "item/commandExecution/requestApproval", params: limited) == [.allowOnce, .deny])
        #expect(throws: CodexRPCError.self) { try CodexProtocol.approval(method: "item/commandExecution/requestApproval", params: limited, decision: .allowSession) }
        let files = try CodexProtocol.approval(method: "item/fileChange/requestApproval", params: .object([:]), decision: .allowSession)
        #expect(files["decision"] == .string("acceptForSession"))
        let cancelOnly: JSONValue = .object(["availableDecisions": .array([.string("cancel")])])
        #expect(try CodexProtocol.approval(method: "item/commandExecution/requestApproval", params: cancelOnly, decision: .deny)["decision"] == .string("cancel"))
        let params: JSONValue = .object(["permissions": .object(["network": .object(["enabled": .bool(true)])])])
        let denied = try CodexProtocol.approval(method: "item/permissions/requestApproval", params: params, decision: .deny)
        #expect(denied["permissions"] == .object([:]) && denied["scope"] == .string("turn"))
        #expect(!CodexProtocol.decisions(method: "item/fileChange/requestApproval", params: .object([:])).contains(.allowAlways))
    }
    @Test func codexAdapterRoutesNativeApprovalsAndAnswers() async throws {
        let store = try store(); defer { try? FileManager.default.removeItem(at: store.root) }
        let rpc = CodexRPC()
        let mock = #"""
        import json, sys
        count = 0
        turn = None
        def emit(value):
            print(json.dumps(value), flush=True)
        for line in sys.stdin:
            msg = json.loads(line)
            method = msg.get('method')
            if method == 'initialize': emit({'id':msg['id'],'result':{}})
            elif method == 'thread/start': emit({'id':msg['id'],'result':{'thread':{'id':'thread'},'model':'test'}})
            elif method == 'turn/start':
                count += 1
                turn = 'turn-' + str(count)
                emit({'id':msg['id'],'result':{'turn':{'id':turn}}})
                emit({'method':'turn/started','params':{'threadId':'thread','turn':{'id':turn}}})
                if count == 1:
                    emit({'id':'approval','method':'item/fileChange/requestApproval','params':{'threadId':'thread','turnId':turn,'itemId':'edit'}})
                else:
                    emit({'id':42,'method':'item/tool/requestUserInput','params':{'threadId':'thread','turnId':turn,'itemId':'question','questions':[{'id':'choice','question':'Continuar?','options':[]}]}})
            elif 'result' in msg:
                if msg['id'] == 'approval':
                    assert msg['result']['decision'] == 'acceptForSession'
                    text = 'APPROVED'
                else:
                    assert msg['id'] == 42
                    assert msg['result']['answers']['choice']['answers'] == ['N\u00e3o']
                    text = 'ANSWERED'
                emit({'method':'item/agentMessage/delta','params':{'threadId':'thread','turnId':turn,'itemId':'answer','delta':text}})
                emit({'method':'turn/completed','params':{'threadId':'thread','turn':{'id':turn,'status':'completed'}}})
        """#
        try await rpc.start(root: store.root, executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", mock])
        let transport = CodexConversationTransport(rpc: rpc); defer { transport.stop() }
        var request: AIPermissionRequest?, completed = false, text = "", disconnected = ""
        var events: [AIEvent] = []
        transport.onDisconnect = { disconnected = $0 }
        transport.onEvent = { event in
            events.append(event)
            if case .permission(let value) = event { request = value }
            if case .textDelta(let delta) = event { text += delta }
            if case .result = event { completed = true }
        }
        let config = AIConversationConfiguration(root: store.root)
        _ = try await transport.prepare(config)
        for input in ["approval", "question"] {
            request = nil; completed = false; text = ""
            _ = try await transport.send(input, configuration: config, schema: nil)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while request == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            let pending = try #require(request)
            if input == "approval" { try transport.respond(to: pending, decision: .allowSession) }
            else { try transport.answer(pending, answers: ["choice": ["Não"]]) }
            while !completed && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(completed, "\(input): \(disconnected), eventos: \(events)")
            #expect(text == (input == "approval" ? "APPROVED" : "ANSWERED"))
        }
    }
    @Test func legacyArgumentsDoNotDiscardCustomModels() {
        let arguments = ClaudeLaunch.arguments(mode: .default, settings: .init(model: "custom-model", effort: "high"), resume: "session")
        #expect(arguments.contains("custom-model") && arguments.contains("session"))
        #expect(ClaudeLaunch.headlessArguments(prompt: "Gerar testes", settings: .init(model: "custom-model")).contains("custom-model"))
    }
}
