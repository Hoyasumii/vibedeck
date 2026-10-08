import Foundation
import Testing
@testable import VibeDeckCore

/// Lines captured from `claude -p --input-format stream-json --output-format stream-json --verbose
/// --include-partial-messages --permission-prompt-tool stdio` (2.1.293), trimmed.
@Suite struct ClaudeStreamTests {
    private func object(_ data: Data) throws -> JSONValue {
        #expect(data.last == UInt8(ascii: "\n"))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private let bashRequest = #"{"type":"control_request","request_id":"r-1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"touch a.txt","description":"Create empty file a.txt","timeout":120000},"description":"Create empty file a.txt","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch a.txt"}],"behavior":"allow","destination":"localSettings"},{"type":"setMode","mode":"acceptEdits","destination":"session"}],"tool_use_id":"toolu_1"}}"#

    private let askRequest = #"{"type":"control_request","request_id":"r-2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","display_name":"AskUserQuestion","input":{"questions":[{"question":"Qual cor você prefere?","header":"Cor","options":[{"label":"Azul","description":"Escrever \"Azul\""},{"label":"Verde"}],"multiSelect":false}]},"tool_use_id":"toolu_2","requires_user_interaction":true}}"#

    private func request(_ line: String) throws -> ClaudePermissionRequest {
        guard case .permission(let r) = ClaudeStream.parse(line) else { throw CancellationError() }
        return r
    }

    @Test func parsesStreamEvents() {
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"init","cwd":"/tmp","session_id":"s-1","model":"claude-haiku-5-5","tools":[]}"#)
            == .initialized(sessionId: "s-1", model: "claude-haiku-5-5"))
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"hook_started","session_id":"s-1"}"#) == .ignored)
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#) == .textStarted)
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}},"parent_tool_use_id":null}"#) == .thinking)
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Você escolheu **"}},"parent_tool_use_id":null}"#) == .textDelta("Você escolheu **"))
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}},"parent_tool_use_id":"toolu_9"}"#) == .ignored)
        #expect(ClaudeStream.parse("não é json") == .ignored)
    }

    @Test func parsesToolUseAndResult() {
        #expect(ClaudeStream.parse(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_3","name":"Bash","input":{"command":"cat cor.txt"}}]},"parent_tool_use_id":null}"#)
            == .toolUse(ClaudeToolUse(id: "toolu_3", name: "Bash", input: ["command": "cat cor.txt"])))
        #expect(ClaudeStream.parse(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Pronto."}]},"parent_tool_use_id":null}"#) == .ignored)
        #expect(ClaudeStream.parse(#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_3","type":"tool_result","content":"Azul","is_error":false}]},"parent_tool_use_id":null}"#)
            == .toolResult(toolUseId: "toolu_3", content: "Azul", isError: false))
        #expect(ClaudeStream.parse(#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_4","type":"tool_result","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"is_error":true}]}}"#)
            == .toolResult(toolUseId: "toolu_4", content: "a\nb", isError: true))
        #expect(ClaudeStream.parse(#"{"type":"result","subtype":"success","is_error":false,"result":"Feito","total_cost_usd":0.0074,"session_id":"s-1"}"#)
            == .result(ClaudeResult(isError: false, text: "Feito", costUSD: 0.0074)))
    }

    @Test func parsesPermissionAndQuestion() throws {
        let bash = try request(bashRequest)
        #expect(bash.requestId == "r-1")
        #expect(bash.toolName == "Bash")
        #expect(bash.input["command"] == "touch a.txt")
        #expect(!bash.isQuestion)

        let ask = try request(askRequest)
        #expect(ask.isQuestion)
        #expect(ask.questions == [ClaudeQuestion(
            question: "Qual cor você prefere?", header: "Cor",
            options: [.init(label: "Azul", description: "Escrever \"Azul\""), .init(label: "Verde", description: nil)],
            multiSelect: false
        )])

        #expect(ClaudeStream.parse(#"{"type":"control_request","request_id":"r-3","request":{"subtype":"hook_callback"}}"#) == .unsupportedControl(requestId: "r-3"))
    }

    @Test func encodesResponses() throws {
        let bash = try request(bashRequest)

        let allow = try object(ClaudeInput.allow(bash))
        #expect(allow["type"] == "control_response")
        #expect(allow["response"]?["request_id"] == "r-1")
        #expect(allow["response"]?["response"]?["behavior"] == "allow")
        #expect(allow["response"]?["response"]?["updatedInput"]?["command"] == "touch a.txt")
        #expect(allow["response"]?["response"]?["updatedInput"]?["timeout"] == .number(120000))
        #expect(allow["response"]?["response"]?["updatedPermissions"] == nil)

        let deny = try object(ClaudeInput.deny(bash, message: "Negado"))
        #expect(deny["response"]?["response"] == ["behavior": "deny", "message": "Negado"])

        let user = try object(ClaudeInput.userMessage("oi"))
        #expect(user == ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": "oi"]]]])

        let interrupt = try object(ClaudeInput.interrupt(requestId: "i-1"))
        #expect(interrupt["request"] == ["subtype": "interrupt"])

        let unsupported = try object(ClaudeInput.unsupported(requestId: "r-3"))
        #expect(unsupported["response"]?["subtype"] == "error")
    }

    @Test func alwaysAllowUsesSuggestionOrWholeTool() throws {
        let bash = try request(bashRequest)
        let always = try object(ClaudeInput.allow(bash, always: .localSettings))
        #expect(always["response"]?["response"]?["updatedPermissions"] == [[
            "type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "touch a.txt"]], "behavior": "allow", "destination": "localSettings",
        ]])
        #expect(ClaudeInput.alwaysAllowRules(for: bash, scope: .session).first?["destination"] == "session")
        #expect(ClaudeInput.ruleLabels(for: bash, scope: .session) == ["Bash(touch a.txt)"])

        // Write only suggests a session mode switch: fall back to a rule for the whole tool.
        let write = try request(#"{"type":"control_request","request_id":"r-4","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/cor.txt","content":"Azul\n"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}}"#)
        #expect(ClaudeInput.alwaysAllowRules(for: write, scope: .localSettings) == [[
            "type": "addRules", "rules": [["toolName": "Write"]], "behavior": "allow", "destination": "localSettings",
        ]])
        #expect(ClaudeInput.ruleLabels(for: write, scope: .localSettings) == ["Write"])
    }

    @Test func answersQuestions() throws {
        let ask = try request(askRequest)
        let single = try object(ClaudeInput.answer(ask, ["Qual cor você prefere?": ["Azul"]]))
        let input = single["response"]?["response"]?["updatedInput"]
        #expect(input?["answers"] == ["Qual cor você prefere?": "Azul"])
        #expect(input?["questions"]?.array?.count == 1)

        let multi = try object(ClaudeInput.answer(ask, ["Qual cor você prefere?": ["Azul", "Verde"]]))
        #expect(multi["response"]?["response"]?["updatedInput"]?["answers"]?["Qual cor você prefere?"] == "Azul, Verde")
    }

    @Test func planModeApproval() throws {
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"status","permissionMode":"default","session_id":"s-1"}"#) == .permissionModeChanged(.default))
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"status","status":"requesting","session_id":"s-1"}"#) == .ignored)

        let exit = try request(##"{"type":"control_request","request_id":"r-5","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":{"plan":"# Plano\n\n1. Criar ola.txt","planFilePath":"/Users/teste/.claude/plans/p.md"},"tool_use_id":"toolu_5","requires_user_interaction":true}}"##)
        #expect(exit.isPlanApproval)
        #expect(!exit.isQuestion)
        #expect(exit.plan == "# Plano\n\n1. Criar ola.txt")

        let approve = try object(ClaudeInput.approvePlan(exit, acceptEdits: false))
        #expect(approve["response"]?["response"]?["behavior"] == "allow")
        #expect(approve["response"]?["response"]?["updatedInput"]?["planFilePath"] == "/Users/teste/.claude/plans/p.md")
        #expect(approve["response"]?["response"]?["updatedPermissions"] == nil)

        let accept = try object(ClaudeInput.approvePlan(exit, acceptEdits: true))
        #expect(accept["response"]?["response"]?["updatedPermissions"] == [["type": "setMode", "mode": "acceptEdits", "destination": "session"]])

        let mode = try object(ClaudeInput.setPermissionMode(.plan, requestId: "m-1"))
        #expect(mode == ["type": "control_request", "request_id": "m-1", "request": ["subtype": "set_permission_mode", "mode": "plan"]])
    }

    @Test func lineBufferSplitsChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data(#"{"a":1}"#.utf8)) == [])
        #expect(buffer.append(Data("\n{\"b\":\"ç".utf8)) == [#"{"a":1}"#])
        #expect(buffer.append(Data("\"}\n\n{\"c\"".utf8)) == [#"{"b":"ç"}"#])
        #expect(buffer.finish() == #"{"c""#)
        #expect(buffer.finish() == nil)
    }

    @Test func linesFromPipeArriveBeforeEOF() async throws {
        let pipe = Pipe()
        var iterator = ClaudeStream.lines(from: pipe.fileHandleForReading).makeAsyncIterator()
        try pipe.fileHandleForWriting.write(contentsOf: Data("um\ndois\n".utf8))
        #expect(await iterator.next() == "um")
        #expect(await iterator.next() == "dois")
        try pipe.fileHandleForWriting.write(contentsOf: Data("três".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(await iterator.next() == "três")
        #expect(await iterator.next() == nil)
    }

    @Test func locatesExecutable() {
        let home = URL(fileURLWithPath: "/Users/teste")
        let installed: Set = ["/Users/teste/.local/bin/claude"]
        #expect(ClaudeCode.locate(home: home, path: "/usr/bin:/bin", isExecutable: installed.contains, loginShellLookup: { nil })?.path
            == "/Users/teste/.local/bin/claude")
        // PATH entries win over the fixed candidates.
        let both: Set = ["/custom/claude", "/opt/homebrew/bin/claude"]
        #expect(ClaudeCode.locate(home: home, path: "/custom", isExecutable: both.contains, loginShellLookup: { nil })?.path == "/custom/claude")
        // Login shell fallback, then nothing.
        #expect(ClaudeCode.locate(home: home, path: nil, isExecutable: { $0 == "/nvm/bin/claude" }, loginShellLookup: { "/nvm/bin/claude\n" })?.path
            == "/nvm/bin/claude")
        #expect(ClaudeCode.locate(home: home, path: nil, isExecutable: { _ in false }, loginShellLookup: { "/nvm/bin/claude" }) == nil)
    }

    @Test func launchArgumentsIncludeModelAndEffortOnlyWhenChosen() {
        let plain = ClaudeLaunch.arguments(mode: .default, model: .automatic, effort: .automatic, resume: nil)
        #expect(!plain.contains("--model"))
        #expect(!plain.contains("--effort"))
        #expect(!plain.contains("--resume"))

        let chosen = ClaudeLaunch.arguments(mode: .plan, model: .sonnet, effort: .xhigh, resume: "s-1")
        #expect(chosen.suffix(6) == ["--model", "sonnet", "--effort", "xhigh", "--resume", "s-1"])
        #expect(chosen.contains("plan"))
    }
}
