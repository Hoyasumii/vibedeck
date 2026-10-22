import Foundation
import Testing
@testable import VibeDeckCore

/// Claude lines captured from `claude -p --output-format stream-json --verbose` (2.1.306) with two parallel
/// Agent calls, trimmed. Codex items follow the `collabAgentToolCall` ThreadItem of `codex app-server
/// generate-json-schema` (codex-cli 0.163.0).
@Suite struct AgentProcessesTests {
    private let started1 = #"{"type":"system","subtype":"task_started","task_id":"a3ae","tool_use_id":"toolu_1","description":"Responder apenas \"um\"","subagent_type":"general-purpose","is_backgrounded":false,"spawn_depth":1,"task_type":"local_agent","prompt":"Responda: um."}"#
    private let started2 = #"{"type":"system","subtype":"task_started","task_id":"a1dc","tool_use_id":"toolu_2","description":"Responder apenas \"dois\"","subagent_type":"general-purpose","is_backgrounded":false,"spawn_depth":1,"task_type":"local_agent","prompt":"Responda: dois."}"#
    private let updated1 = #"{"type":"system","subtype":"task_updated","task_id":"a3ae","patch":{"status":"completed","end_time":1792615803381}}"#
    private let done1 = #"{"type":"system","subtype":"task_notification","task_id":"a3ae","tool_use_id":"toolu_1","status":"completed","summary":"um"}"#
    private let done2 = #"{"type":"system","subtype":"task_notification","task_id":"a1dc","tool_use_id":"toolu_2","status":"completed","summary":"dois"}"#

    private func track(_ lines: [String], into tracker: inout AgentProcessTracker) {
        for line in lines { tracker.apply(ClaudeStream.parse(line), provider: .claude) }
    }

    private func state(_ tracker: AgentProcessTracker, _ id: String) -> AgentProcessState? {
        tracker.processes.first { $0.id == id }?.state
    }

    @Test func parsesClaudeTaskLines() {
        #expect(ClaudeStream.parse(started1) == .agents([.started(id: "toolu_1", alias: "a3ae", name: "general-purpose", detail: "Responder apenas \"um\"")]))
        #expect(ClaudeStream.parse(done1) == .agents([.finished(id: "toolu_1", state: .succeeded)]))
        #expect(ClaudeStream.parse(updated1) == .agents([.finished(id: "a3ae", state: .succeeded)]))
        // Background shells are tasks too, but not agents.
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"task_started","task_id":"b1","tool_use_id":"toolu_9","task_type":"local_bash"}"#) == .ignored)
        // Text of subagents is still not shown in the chat.
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}},"parent_tool_use_id":"toolu_1"}"#) == .ignored)
    }

    @Test func overlappingClaudeSubagentsRunUntilTheirOwnEnd() {
        var tracker = AgentProcessTracker()
        track([#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Agent","input":{"description":"um"}}]},"parent_tool_use_id":null}"#,
               started1, started2], into: &tracker)
        #expect(tracker.running.map(\.id) == [AgentProcessTracker.mainID, "toolu_1", "toolu_2"])
        #expect(tracker.processes.first { $0.id == "toolu_1" }?.parentID == AgentProcessTracker.mainID)

        track([done1], into: &tracker)
        #expect(state(tracker, "toolu_1") == .succeeded)
        #expect(state(tracker, "toolu_2") == .running)

        track([done2, #"{"type":"result","subtype":"success","is_error":false,"result":"fim"}"#], into: &tracker)
        #expect(tracker.running.isEmpty)
        #expect(state(tracker, AgentProcessTracker.mainID) == .succeeded)
    }

    @Test func nestedSubagentsKeepTheirParent() {
        var tracker = AgentProcessTracker()
        let childOf = { (parent: String, id: String) in
            #"{"type":"system","subtype":"task_started","task_id":"t-\#(id)","tool_use_id":"\#(id)","subagent_type":"Explore","task_type":"local_agent","parent_tool_use_id":"\#(parent)"}"#
        }
        track([started1, started2, childOf("toolu_1", "toolu_1a"), childOf("toolu_2", "toolu_2a"), childOf("toolu_1", "toolu_1b")], into: &tracker)
        let parents = Dictionary(uniqueKeysWithValues: tracker.processes.map { ($0.id, $0.parentID) })
        #expect(parents["toolu_1a"] == "toolu_1")
        #expect(parents["toolu_1b"] == "toolu_1")
        #expect(parents["toolu_2a"] == "toolu_2")
        #expect(parents["toolu_1"] == AgentProcessTracker.mainID)
        #expect(tracker.running.count == 6)
    }

    @Test func failureOrInterruptionEndsOnlyThatProcess() {
        var tracker = AgentProcessTracker()
        track([started1, started2], into: &tracker)
        track([#"{"type":"system","subtype":"task_notification","task_id":"a3ae","tool_use_id":"toolu_1","status":"failed"}"#], into: &tracker)
        #expect(state(tracker, "toolu_1") == .failed)
        #expect(state(tracker, "toolu_2") == .running)

        var other = AgentProcessTracker()
        track([started1, started2, #"{"type":"system","subtype":"task_notification","task_id":"a1dc","tool_use_id":"toolu_2","status":"killed"}"#], into: &other)
        #expect(state(other, "toolu_2") == .interrupted)
        #expect(state(other, "toolu_1") == .running)
        #expect(other.processes.first { $0.id == "toolu_2" }?.endedAt != nil)
    }

    @Test func responseTextNeverCreatesProcesses() {
        var tracker = AgentProcessTracker()
        track([#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#,
               #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Lancei o subagente Explore e o agente revisor (task_started)."}},"parent_tool_use_id":null}"#],
              into: &tracker)
        #expect(tracker.processes.map(\.id) == [AgentProcessTracker.mainID])
    }

    @Test func waitingForAnAnswerIsNotActiveWork() {
        var tracker = AgentProcessTracker()
        track([started1, done1, #"{"type":"result","subtype":"success","is_error":false,"result":"PERGUNTA"}"#], into: &tracker)
        #expect(tracker.running.isEmpty)
        tracker.apply(.result(ClaudeResult(isError: false, text: nil, costUSD: nil, isInterrupted: true)), provider: .claude)
        #expect(state(tracker, AgentProcessTracker.mainID) == .interrupted)
    }

    @Test func codexCollabCallsStartAndEndEachAgent() {
        func item(_ method: String, _ tool: String, receivers: [String] = [], states: [String: String] = [:], status: String = "inProgress") -> AIEvent {
            CodexProtocol.event(method, ["threadId": "main-thread", "turnId": "turn-1", "item": .object([
                "type": "collabAgentToolCall", "id": .string(UUID().uuidString), "tool": .string(tool), "status": .string(status),
                "senderThreadId": "main-thread", "receiverThreadIds": .array(receivers.map(JSONValue.string)), "prompt": "Revise o diff",
                "agentsStates": .object(states.mapValues { .object(["status": .string($0)]) }),
            ])])
        }
        var tracker = AgentProcessTracker()
        for event in [
            item("item/started", "spawnAgent", receivers: ["th-a"]),
            item("item/completed", "spawnAgent", receivers: ["th-a"], states: ["th-a": "pendingInit"], status: "completed"),
            item("item/started", "spawnAgent", receivers: ["th-b"]),
            item("item/completed", "spawnAgent", receivers: ["th-b"], states: ["th-b": "running"], status: "completed"),
        ] { tracker.apply(event, provider: .codex) }
        #expect(tracker.running.map(\.id) == [AgentProcessTracker.mainID, "th-a", "th-b"])
        #expect(tracker.processes.first { $0.id == "th-a" }?.parentID == AgentProcessTracker.mainID)
        #expect(tracker.processes.first { $0.id == "th-a" }?.detail == "Revise o diff")

        tracker.apply(item("item/completed", "wait", receivers: ["th-a"], states: ["th-a": "completed", "th-b": "running"], status: "completed"), provider: .codex)
        #expect(state(tracker, "th-a") == .succeeded)
        #expect(state(tracker, "th-b") == .running)

        tracker.apply(item("item/completed", "wait", receivers: ["th-b"], states: ["th-b": "errored"], status: "completed"), provider: .codex)
        #expect(state(tracker, "th-b") == .failed)
        #expect(state(tracker, "th-a") == .succeeded)

        // A status for an agent never started is not a process.
        tracker.apply(item("item/completed", "wait", states: ["th-x": "running"]), provider: .codex)
        #expect(!tracker.processes.contains { $0.id == "th-x" })
    }

    @Test func codexSenderOtherThanTheConversationIsTheParent() {
        let event = CodexProtocol.event("item/started", ["threadId": "main-thread", "item": [
            "type": "collabAgentToolCall", "id": "c1", "tool": "spawnAgent", "status": "inProgress",
            "senderThreadId": "th-a", "receiverThreadIds": ["th-a1"], "agentsStates": [:],
        ]])
        #expect(event == .agents([.started(id: "th-a1", name: "Subagente", detail: nil, parentID: "th-a")]))
    }

    @Test func reopenedProcessesNeedConfirmation() {
        var tracker = AgentProcessTracker()
        track([started1, started2, done2], into: &tracker)
        let restored = AgentProcessTracker(restoring: tracker.processes)
        #expect(restored.running.isEmpty)
        #expect(state(restored, "toolu_1") == .unconfirmed)
        #expect(state(restored, "toolu_2") == .succeeded)

        var confirmed = restored
        confirmed.apply(.started(id: "toolu_1", name: "general-purpose"))
        #expect(state(confirmed, "toolu_1") == .running)
    }

    @Test func providerEndInterruptsWhatStillRan() {
        var tracker = AgentProcessTracker()
        track([started1, started2, done1], into: &tracker)
        tracker.providerEnded()
        #expect(tracker.running.isEmpty)
        #expect(state(tracker, "toolu_1") == .succeeded)
        #expect(state(tracker, "toolu_2") == .interrupted)
    }

    @Test func chatKeepsItsRunAndProcesses() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vd-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClaudeChatStore(dir: dir)
        var chat = ClaudeChat(title: "Workflow · Revisão", messages: [ClaudeChatMessage(role: .notice, text: "▶ Etapa planejar")])
        chat.workflowRun = "revisao/run-1"
        chat.agentProcesses = [AgentProcess(id: "toolu_1", name: "Explore", state: .running)]
        try store.save(chat)
        chat.title = "Outro nome"; chat.messages = []
        try store.save(chat)
        let loaded = try #require(store.load(chat.id))
        #expect(loaded.workflowRun == "revisao/run-1")
        #expect(loaded.agentProcesses.map(\.id) == ["toolu_1"])

        // Older chats have neither key; empty values are not written.
        let old = try VDJSON.decoder.decode(ClaudeChat.self, from: Data(#"{"title":"Antiga","messages":[]}"#.utf8))
        #expect(old.workflowRun == nil && old.agentProcesses.isEmpty)
        let json = String(decoding: try VDJSON.encode(old), as: UTF8.self)
        #expect(!json.contains("workflowRun") && !json.contains("agentProcesses"))
    }

    @Test func traversedFollowsHistoryWithBranchesAndLoops() {
        var run = WorkflowRun(workflow: "w", input: nil, start: "a")
        run.history = [
            WorkflowRunEntry(step: "a", next: "b"),
            WorkflowRunEntry(step: "b", next: "a"),
            WorkflowRunEntry(step: "a", next: "c"),
            WorkflowRunEntry(step: "c", next: nil),
            WorkflowRunEntry(step: "x", next: "y", cycle: 0),
        ]
        #expect(run.traversed == [.init(from: "a", to: "b"), .init(from: "b", to: "a"), .init(from: "a", to: "c"), .init(from: "c", to: nil)])
        #expect(!run.traversed.contains(.init(from: "b", to: "c")))
    }
}
