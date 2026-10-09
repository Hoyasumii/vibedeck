import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct CodexTests {
    private func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func legacyAndProviderPersistence() throws {
        let legacy = try VDJSON.decoder.decode(ClaudeChat.self, from: Data(#"{"title":"Antiga","sessionId":"claude-session"}"#.utf8))
        #expect(legacy.provider == .claude)
        let chat = ClaudeChat(title: "Codex", provider: .codex, sessionId: "codex-thread", createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1000), messages: [.init(role: .assistant, text: "Olá")])
        #expect(try VDJSON.decoder.decode(ClaudeChat.self, from: VDJSON.encode(chat)) == chat)
        let run = WorkflowRun(workflow: "review", input: "feature", start: "first", provider: .codex)
        #expect(try VDJSON.decoder.decode(WorkflowRun.self, from: VDJSON.encode(run)).provider == .codex)
        #expect(try VDJSON.decoder.decode(WorkflowRun.self, from: Data(#"{"workflow":"review"}"#.utf8)).provider == .claude)
    }
    @Test func nativeAgentTOMLAndInvalidInput() throws {
        let agent = try CodexAgentFile.parse(#"""
        name = "reviewer"
        description = 'Read only # reviewer'
        model = "codex-model"
        model_reasoning_effort = "high"
        developer_instructions = """
        Read the code.
        Return "APROVADO".
        """
        [mcp_servers.docs]
        command = "docs"
        """#, fallbackName: "ignored")
        #expect(agent.name == "reviewer")
        #expect(agent.description == "Read only # reviewer")
        #expect(agent.prompt.contains("Return \"APROVADO\"."))
        #expect(agent.effort == "high")
        #expect(throws: (any Error).self) { try CodexAgentFile.parse("name = 'bad'", fallbackName: "bad") }
        #expect(throws: (any Error).self) { try CodexAgentFile.parse("developer_instructions = \"unterminated", fallbackName: "bad") }
        let unicode = try CodexAgentFile.parse(#"developer_instructions = "Ol\u00e1\nRevise""#, fallbackName: "unicode")
        #expect(unicode.prompt == "Olá\nRevise")
    }
    @Test func importsPrecedenceAndOverwrite() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let local = root.appending(path: "project-agents"), user = root.appending(path: "user-agents")
        for dir in [local, user] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try "name = 'reviewer'\ndeveloper_instructions = 'Project'\nmodel = 'codex-model'".write(to: local.appending(path: "review.toml"), atomically: true, encoding: .utf8)
        try "name = 'reviewer'\ndeveloper_instructions = 'User'".write(to: user.appending(path: "review.toml"), atomically: true, encoding: .utf8)
        try "name = 'broken'".write(to: user.appending(path: "broken.toml"), atomically: true, encoding: .utf8)
        let result = try store.importAgents(provider: .codex, from: [local, user])
        #expect(result.slugs == ["reviewer"])
        #expect(result.warnings.count == 1)
        #expect(try store.loadAgent("reviewer").prompt == "Project")
        #expect(try store.loadAgent("reviewer").providerSettings?["codex"]?.model == "codex-model")
        _ = try store.updateAgent("reviewer") { $0.nextSteps = [.init(ref: "next")]; $0.prompt = "Human edit" }
        #expect(try store.importAgents(provider: .codex, from: [local]).slugs.isEmpty)
        _ = try store.importAgents(provider: .codex, from: [local], overwrite: true)
        #expect(try store.loadAgent("reviewer").nextSteps == [.init(ref: "next")])
        #expect(try store.expandAICommand("/agent:reviewer input").contains("Project"))
        let command = try store.createCommand(title: "Commit", prompt: "Commit $ARGUMENTS")
        #expect(try store.expandAICommand("/\(command.slug) fix login") == "Commit fix login")
    }
    @Test @MainActor func skillsKeepResourcePaths() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let sources = root.appending(path: "native-skills"), folder = sources.appending(path: "docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: docs\ndescription: Write docs\n---\nRead references/example.md".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let result = try await store.importSkills(provider: .codex, from: [sources])
        #expect(result.slugs == ["docs"])
        let skill = try store.loadSkill("docs")
        let source = URL(fileURLWithPath: try #require(skill.sourcePath))
        #expect(try Data(contentsOf: source) == Data(contentsOf: folder.appending(path: "SKILL.md")))
        #expect(source.deletingLastPathComponent().lastPathComponent == "docs")
        #expect(try store.expandAICommand("/docs guide").contains(source.deletingLastPathComponent().path))
    }
    @Test func codexRequestsAndQuestionsPreserveRPCIds() throws {
        let id = JSONValue.number(42)
        let params: JSONValue = .object(["questions": .array([.object(["id": .string("decision"), "question": .string("Qual?"), "header": .string("Escolha"), "options": .array([.object(["label": .string("A")])])])])])
        let request = try #require(CodexProtocol.permission(id: id, method: "item/tool/requestUserInput", params: params))
        #expect(request.id == "42")
        #expect(request.isQuestion)
        #expect(request.questions.first?.question == "Qual?")
        let answer = CodexProtocol.answer(params: params, answers: ["Qual?": ["A"]])
        #expect(answer["answers"]?["decision"]?["answers"]?.array == [.string("A")])
        #expect(CodexProtocol.key(.string("42")) != CodexProtocol.key(id))
        let denied = CodexProtocol.permission(id: .string("edit"), method: "item/fileChange/requestApproval", params: .object(["reason": .string("edit config")]))
        #expect(denied?.toolName == "Edit")
    }
    @Test func codexModesNeverBypassSandbox() {
        let root = URL(fileURLWithPath: "/tmp/project")
        for mode in ClaudePermissionMode.allCases {
            let params = CodexProtocol.threadParameters(root: root, mode: mode)
            #expect(params["approvalPolicy"]?.string != "never")
            #expect(params["sandbox"]?.string != "danger-full-access")
        }
        #expect(CodexProtocol.threadParameters(root: root, mode: .plan)["sandbox"] == .string("read-only"))
        let params = CodexProtocol.turnParameters(thread: "t", text: "plan", mode: .plan, model: "available-model", effort: "high")
        #expect(params["collaborationMode"]?["mode"] == .string("plan"))
        #expect(params["sandboxPolicy"]?["type"] == .string("readOnly"))
    }
    @Test func codexAutoReviewIsExplicitForThreadsAndTurns() {
        let root = URL(fileURLWithPath: "/tmp/project")
        for enabled in [true, false] {
            for mode in ClaudePermissionMode.allCases {
                let thread = CodexProtocol.threadParameters(root: root, mode: mode, autoReview: enabled)
                let turn = CodexProtocol.turnParameters(thread: "resumed-thread", text: "Continue", mode: mode, model: nil, effort: nil, autoReview: enabled)
                for params in [thread, turn] {
                    #expect(params["approvalPolicy"] == .string("on-request"))
                    #expect(params["approvalsReviewer"] == .string(enabled ? "auto_review" : "user"))
                }
                #expect(thread["sandbox"] == .string(mode == .plan ? "read-only" : "workspace-write"))
                #expect(turn["sandboxPolicy"]?["type"] == .string(mode == .plan ? "readOnly" : "workspaceWrite"))
            }
        }
        #expect(CodexProtocol.threadParameters(root: root, mode: .default)["approvalsReviewer"] == .string("user"))
    }

    @Test func workflowProviderAndModelCompatibility() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let (agent, _) = try store.createAgent(title: "Review", model: "sonnet", prompt: "Review code")
        let (workflow, _) = try store.createWorkflow(title: "Review flow")
        _ = try store.addWorkflowStep(to: workflow, kind: .agent, target: agent)
        let (ref, _, _) = try store.startRun(workflow, input: "feature", provider: .codex)
        let fallback = try store.runProviderSettings(ref, availableModels: ["codex-model"], fallback: "codex-model")
        #expect(fallback.settings.model == "codex-model")
        #expect(fallback.warning != nil)
        _ = try store.updateAgent(agent) { $0.providerSettings = ["codex": .init(model: "codex-model", effort: "high")] }
        let configured = try store.runProviderSettings(ref, availableModels: ["codex-model"], fallback: nil)
        #expect(configured.settings.effort == "high")
        #expect(configured.warning == nil)
        let resumed = try store.startRun(workflow, input: "feature", provider: .claude)
        #expect(resumed.run.provider == .codex)
        let prompt = WorkflowOrchestration.orchestratorPrompt(ref: ref, title: "Review", input: nil, provider: .codex)
        #expect(!prompt.contains("`Agent`"))
        #expect(!prompt.contains("AskUserQuestion"))
    }
    @Test func mcpConfigurationPreservesUserSettings() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: ".codex/config.toml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "model = 'my-model'\n[mcp_servers.docs]\ncommand = 'docs'\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        try CodexMCP.install(root: root, cli: "/tmp/bin with spaces/vibedeck")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix(original))
        #expect(text.contains("/tmp/bin with spaces/vibedeck"))
        #expect(text.contains("--root"))
        #expect(throws: (any Error).self) { try CodexMCP.install(root: root, cli: "/tmp/cli") }
        try CodexMCP.install(root: root, cli: "/tmp/new", force: true)
        #expect(try String(contentsOf: file, encoding: .utf8).components(separatedBy: "[mcp_servers.vibedeck]").count == 2)
        try CodexMCP.uninstall(root: root)
        #expect(try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == original.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    @Test func streamAndQuotaData() {
        #expect(CodexProtocol.event("item/agentMessage/delta", .object(["delta": .string("Olá")])) == .textDelta("Olá"))
        let limits = CodexRateLimit.list(.object(["rateLimits": .object(["primary": .object(["usedPercent": .number(30), "windowDurationMins": .number(300), "resetsAt": .number(1000)])])]))
        #expect(limits.first?.usedPercent == 30)
        #expect(limits.first?.resetsAt == Date(timeIntervalSince1970: 1000))
        #expect(CodexRateLimit.list(.null).isEmpty)
        #expect(CloudSession.parseSessionURL("created https://chatgpt.com/codex/tasks/task_123", provider: .codex)?.absoluteString == "https://chatgpt.com/codex/tasks/task_123")
    }

    @Test func checksWithinSameSecondHaveStableOrder() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let (_, rule) = try store.addRule(Rule(text: "Check changes"), toTopic: "Rules")
        let failed = try store.submitCheck(task: "old", files: ["test.swift"], answers: [.init(ruleId: rule.id.uuidString, verdict: .fail)])
        var passed = try store.submitCheck(task: "new", files: ["test.swift"], answers: [.init(ruleId: rule.id.uuidString, verdict: .pass)])
        passed.createdAt = failed.createdAt
        let files = try FileManager.default.contentsOfDirectory(at: store.checksDir, includingPropertiesForKeys: nil)
        for file in files {
            let check = try VDJSON.decoder.decode(RuleCheck.self, from: Data(contentsOf: file))
            if check.id == passed.id {
                try VDJSON.encode(passed).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: failed.createdAt.addingTimeInterval(2)], ofItemAtPath: file.path)
            } else { try FileManager.default.setAttributes([.modificationDate: failed.createdAt], ofItemAtPath: file.path) }
        }
        #expect(try store.listChecks().first?.id == passed.id)
        #expect(try store.unverifiedChanges([("test.swift", failed.createdAt.addingTimeInterval(-1))]).isEmpty)
    }

    @Test @MainActor func liveCodexSmokeWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VIBEDECK_CODEX_SMOKE"] == "1" else { return }
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let rpc = CodexRPC(); defer { rpc.stop() }
        try await rpc.start(root: root)
        let models = CodexModel.list(try await rpc.request("model/list", params: ["limit": .number(100)]))
        #expect(!models.isEmpty)
        _ = try await rpc.request("skills/list", params: ["cwds": .array([.string(root.path)])])
        _ = try ProjectStore.initialize(at: root)
        let cli = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/vibedeck").path
        try #require(FileManager.default.isExecutableFile(atPath: cli))
        let started = try await rpc.request("thread/start", params: ["cwd": .string(root.path), "ephemeral": .bool(true), "sandbox": .string("read-only"), "approvalPolicy": .string("never"), "config": .object(CodexMCP.sessionConfig(root: root, cli: cli))])
        let thread = try #require(started["thread"]?["id"]?.string)
        let catalog = try await rpc.request("mcpServerStatus/list", params: ["threadId": .string(thread), "serverName": .string("vibedeck")])
        let server = try #require(catalog["data"]?.array?.first { $0["name"]?.string == "vibedeck" })
        #expect(server["tools"]?["get_project"] != nil)
        let project = try await rpc.request("mcpServer/tool/call", params: ["threadId": .string(thread), "server": .string("vibedeck"), "tool": .string("get_project"), "arguments": .object([:])])
        #expect(project["isError"] != .bool(true))
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["ok": .object(["type": .string("boolean")])]), "required": .array([.string("ok")]), "additionalProperties": .bool(false)])
        let result = try await CodexReadOnly().run(root: root, prompt: "Retorne apenas o objeto JSON {\"ok\":true}. Não execute ferramentas.", schema: schema)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(result.utf8))["ok"] == .bool(true))
    }

    @Test @MainActor func transportFragmentationErrorsTimeoutAndCancellation() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let rpc = CodexRPC(); defer { rpc.stop() }
        let mock = #"""
        import json, sys, time
        for line in sys.stdin:
            msg = json.loads(line)
            if 'id' not in msg: continue
            method = msg['method']
            if method == 'hang': continue
            if method == 'fail': out = {'id':msg['id'],'error':{'code':-1,'message':'fixture failure'}}
            else: out = {'id':msg['id'],'result':{'ok':True}}
            wire = json.dumps(out) + '\n'
            sys.stdout.write(wire[:5]); sys.stdout.flush()
            time.sleep(0.01)
            sys.stdout.write(wire[5:]); sys.stdout.flush()
        """#
        try await rpc.start(root: root, executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", mock])
        let result = try await rpc.request("echo")
        #expect(result["ok"] == .bool(true))
        do { _ = try await rpc.request("fail"); Issue.record("Expected error") } catch { #expect(error.localizedDescription.contains("fixture failure")) }
        do { _ = try await rpc.request("hang", timeout: .milliseconds(30)); Issue.record("Expected timeout") } catch { #expect(error.localizedDescription.contains("tempo")) }
        let task = Task { try await rpc.request("hang") }
        await Task.yield(); task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
        let waiting = Task { try await rpc.request("hang") }
        await Task.yield(); rpc.stop()
        do { _ = try await waiting.value; Issue.record("Expected disconnect") } catch { #expect(error is CodexRPCError) }
    }
}
