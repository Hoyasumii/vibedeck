import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ClaudeChatsTests {
    private func tempStore() -> ClaudeChatStore {
        ClaudeChatStore(dir: FileManager.default.temporaryDirectory.appending(path: "vibedeck-chats-\(UUID().uuidString)"))
    }

    @Test func savesListsAndDeletes() throws {
        let store = tempStore()
        defer { try? store.deleteAll() }
        #expect(store.list().isEmpty)

        let old = ClaudeChat(title: "Antiga", sessionId: "s-1", createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1000), messages: [
            ClaudeChatMessage(role: .user, text: "oi"),
        ])
        let new = ClaudeChat(title: "Nova", createdAt: Date(timeIntervalSince1970: 2000), updatedAt: Date(timeIntervalSince1970: 2000), messages: [
            ClaudeChatMessage(role: .user, text: "veja", mentions: [old.id]),
            ClaudeChatMessage(role: .tool, text: "Bash", toolName: "Bash", summary: "ls", result: "a.txt"),
        ])
        try store.save(old)
        try store.save(new)

        #expect(store.list().map(\.title) == ["Nova", "Antiga"])
        #expect(store.load(new.id) == new)
        #expect(store.load(UUID()) == nil)

        try store.delete(old.id)
        #expect(store.list().map(\.id) == [new.id])
        try store.deleteAll()
        #expect(store.list().isEmpty)
    }

    @Test func lenientDecodeOfHandWrittenChat() throws {
        let json = #"{"title":"À mão","messages":[{"text":"oi"}]}"#
        let chat = try VDJSON.decoder.decode(ClaudeChat.self, from: Data(json.utf8))
        #expect(chat.title == "À mão")
        #expect(chat.sessionId == nil)
        #expect(chat.messages == [ClaudeChatMessage(role: .notice, text: "oi")])
    }

    @Test func titleFromFirstLine() {
        #expect(ClaudeChat.title(from: "  Corrigir o login\nmais detalhes") == "Corrigir o login")
        #expect(ClaudeChat.title(from: "   ") == ClaudeChat.untitled)
        let long = String(repeating: "a", count: 60)
        #expect(ClaudeChat.title(from: long) == String(repeating: "a", count: 40) + "…")
    }

    @Test func contextJSONHasTheWholeChat() throws {
        let chat = ClaudeChat(title: "Login", messages: [
            ClaudeChatMessage(role: .user, text: "como funciona o login?", mentions: [UUID()]),
            ClaudeChatMessage(role: .assistant, text: "Usa OAuth."),
        ])
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(chat.contextJSON().utf8))
        #expect(json["title"]?.string == "Login")
        let messages = json["messages"]?.array ?? []
        #expect(messages.map { $0["text"]?.string } == ["como funciona o login?", "Usa OAuth."])
        #expect(messages.first?["mentions"] == nil)
    }

    @Test func wireTextAppendsMentionedChats() {
        #expect(ClaudeChat.wireText("oi", mentioning: []) == "oi")
        let a = ClaudeChat(title: "A \"x\"", messages: [ClaudeChatMessage(role: .user, text: "mensagem de A")])
        let b = ClaudeChat(title: "B", messages: [ClaudeChatMessage(role: .assistant, text: "resposta de B")])
        let text = ClaudeChat.wireText("compare", mentioning: [a, b])
        #expect(text.hasPrefix("compare\n\n"))
        #expect(text.components(separatedBy: "<conversa-mencionada").count == 3)
        #expect(text.contains(#"titulo="A 'x'""#))
        #expect(text.contains("mensagem de A") && text.contains("resposta de B"))
    }
}
