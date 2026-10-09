import SwiftUI
import VibeDeckCore

/// The project's saved Claude conversations, shown when no chat is open.
struct ClaudeChatList: View {
    @Environment(AISession.self) private var claude
    @State private var renaming: ClaudeChat?
    @State private var deleting: ClaudeChat?
    @State private var confirmingClearHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if claude.chats.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma conversa", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text("As conversas com o Claude ficam salvas aqui para você voltar a elas.")
                } actions: {
                    Button("Nova conversa") { claude.newChat() }
                        .buttonStyle(.glassProminent)
                }
            } else {
                List(claude.chats) { chat in
                    Button { claude.open(chat.id) } label: { ChatRow(chat: chat) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Abrir") { claude.open(chat.id) }
                            Button("Renomear…") { renaming = chat }
                            Button("Limpar conversa") { claude.clear(chat.id) }
                                .disabled(chat.messages.isEmpty && chat.sessionId == nil)
                            Divider()
                            Button("Apagar…", role: .destructive) { deleting = chat }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                HStack {
                    Button("Limpar histórico", role: .destructive) { confirmingClearHistory = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Nova conversa") { claude.newChat() }
                        .buttonStyle(.glassProminent)
                }
                .font(.callout)
                .padding(10)
            }
        }
        .renameChatAlert($renaming)
        .confirmationDialog("Apagar todas as conversas deste projeto?", isPresented: $confirmingClearHistory) {
            Button("Apagar todas", role: .destructive) { claude.clearHistory() }
        } message: {
            Text("O histórico salvo no VibeDeck é removido e não pode ser recuperado.")
        }
        .confirmationDialog(
            "Apagar \"\(deleting?.title ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { chat in
            Button("Apagar", role: .destructive) { claude.delete(chat.id) }
        }
    }
}

private struct ChatRow: View {
    let chat: ClaudeChat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.title + " · " + chat.provider.title)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(chat.updatedAt, format: .relative(presentation: .named))
                Text("·")
                Text("\(count) mensagens")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var count: Int {
        chat.messages.filter { $0.role == .user || $0.role == .assistant }.count
    }
}

/// Title of the open chat, with its actions.
struct ClaudeChatHeader: View {
    @Environment(AISession.self) private var claude
    @State private var renaming: ClaudeChat?
    @State private var confirmingClear = false

    var body: some View {
        if let chat = claude.current {
            HStack(spacing: 6) {
                Button { claude.leaveChat() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Sair da conversa (ela fica salva)")
                Menu {
                    Button("Renomear…") { renaming = chat }
                    Button("Limpar conversa…") { confirmingClear = true }
                        .disabled(claude.entries.isEmpty && chat.sessionId == nil)
                    Divider()
                    Button("Sair da conversa") { claude.leaveChat() }
                } label: {
                    Text(chat.title + " · " + chat.provider.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .renameChatAlert($renaming)
            .confirmationDialog("Limpar esta conversa?", isPresented: $confirmingClear) {
                Button("Limpar", role: .destructive) { claude.clear(chat.id) }
            } message: {
                Text("As mensagens e o contexto da IA são apagados; a conversa continua na lista com o mesmo nome.")
            }
        }
    }
}

/// Chips for the chats mentioned in the message being written.
struct MentionChips: View {
    @Environment(AISession.self) private var claude
    @Binding var mentions: [UUID]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(mentions, id: \.self) { id in
                    HStack(spacing: 4) {
                        Text("@" + (claude.title(of: id) ?? "conversa apagada"))
                            .lineLimit(1)
                        Button { mentions.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remover menção")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: .capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Files attached to the draft; Claude gets their absolute paths with the message.
struct AttachmentChips: View {
    @Binding var files: [URL]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(files, id: \.self) { url in
                    HStack(spacing: 4) {
                        Label(url.lastPathComponent, systemImage: "paperclip")
                            .lineLimit(1)
                        Button { files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remover anexo")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: .capsule)
                    .help(url.path)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Picks other chats to mention; their whole transcript is sent as JSON with the message.
struct MentionPicker: View {
    @Environment(AISession.self) private var claude
    @Binding var mentions: [UUID]
    var onPick: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mencionar conversa")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            if candidates.isEmpty {
                Text("Nenhuma outra conversa salva.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(candidates) { chat in
                Button {
                    mentions.append(chat.id)
                    onPick()
                } label: {
                    Text(chat.title + " · " + chat.provider.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 240)
    }

    private var candidates: [ClaudeChat] {
        claude.chats.filter { $0.id != claude.current?.id && !mentions.contains($0.id) }
    }
}

private struct RenameChatAlert: ViewModifier {
    @Environment(AISession.self) private var claude
    @Binding var chat: ClaudeChat?
    @State private var title = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Renomear conversa",
                isPresented: Binding(get: { chat != nil }, set: { if !$0 { chat = nil } }),
                presenting: chat
            ) { chat in
                TextField("Nome", text: $title)
                Button("Cancelar", role: .cancel) {}
                Button("Renomear") { claude.rename(chat.id, to: title) }
            }
            .onChange(of: chat?.id) { title = chat?.title ?? "" }
    }
}

extension View {
    func renameChatAlert(_ chat: Binding<ClaudeChat?>) -> some View {
        modifier(RenameChatAlert(chat: chat))
    }
}
