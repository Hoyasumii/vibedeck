import SwiftUI

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
                    LoggedButton("Nova conversa") { claude.newChat() }.loggedControl(control: "claude_chat_list.button_1", label: "Nova conversa")
                        .buttonStyle(.glassProminent)
                }
            } else {
                List(claude.chats) { chat in
                    LoggedButton { claude.open(chat.id) } label: { ChatRow(chat: chat) }.loggedControl(control: "claude_chat_list.button_2", label: "Ativar controle")
                        .buttonStyle(.plain)
                        .contextMenu {
                            LoggedButton("Abrir") { claude.open(chat.id) }.loggedControl(control: "claude_chat_list.button_3", label: "Abrir")
                            LoggedButton("Renomear…") { renaming = chat }.loggedControl(control: "claude_chat_list.button_4", label: "Renomear…")
                            LoggedButton("Limpar conversa") { claude.clear(chat.id) }.loggedControl(control: "claude_chat_list.button_5", label: "Limpar conversa")
                                .disabled(chat.messages.isEmpty && chat.sessionId == nil)
                            Divider()
                            LoggedButton("Apagar…", role: .destructive) { deleting = chat }.loggedControl(control: "claude_chat_list.button_6", label: "Apagar…")
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                HStack {
                    LoggedButton("Limpar histórico", role: .destructive) { confirmingClearHistory = true }.loggedControl(control: "claude_chat_list.button_7", label: "Limpar histórico")
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    LoggedButton("Nova conversa") { claude.newChat() }.loggedControl(control: "claude_chat_list.button_8", label: "Nova conversa")
                        .buttonStyle(.glassProminent)
                }
                .font(.callout)
                .padding(10)
            }
        }
        .renameChatAlert($renaming)
        .confirmationDialog("Apagar todas as conversas deste projeto?", isPresented: $confirmingClearHistory) {
            LoggedButton("Apagar todas", role: .destructive) { claude.clearHistory() }.loggedControl(control: "claude_chat_list.button_9", label: "Apagar todas")
        } message: {
            Text("O histórico salvo no VibeDeck é removido e não pode ser recuperado.")
        }
        .confirmationDialog(
            "Apagar \"\(deleting?.title ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { chat in
            LoggedButton("Apagar", role: .destructive) { claude.delete(chat.id) }.loggedControl(control: "claude_chat_list.button_10", label: "Apagar")
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
                LoggedButton { claude.leaveChat() } label: { Image(systemName: "chevron.left") }.loggedControl(control: "claude_chat_list.button_11", label: "Ativar controle")
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Sair da conversa (ela fica salva)")
                Menu {
                    LoggedButton("Renomear…") { renaming = chat }.loggedControl(control: "claude_chat_list.button_12", label: "Renomear…")
                    LoggedButton("Limpar conversa…") { confirmingClear = true }.loggedControl(control: "claude_chat_list.button_13", label: "Limpar conversa…")
                        .disabled(claude.entries.isEmpty && chat.sessionId == nil)
                    Divider()
                    LoggedButton("Sair da conversa") { claude.leaveChat() }.loggedControl(control: "claude_chat_list.button_14", label: "Sair da conversa")
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
                LoggedButton("Limpar", role: .destructive) { claude.clear(chat.id) }.loggedControl(control: "claude_chat_list.button_15", label: "Limpar")
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
                        LoggedButton { mentions.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }.loggedControl(control: "claude_chat_list.button_16", label: "Ativar controle")
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
                        LoggedButton { files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }.loggedControl(control: "claude_chat_list.button_17", label: "Ativar controle")
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
                LoggedButton {
                    mentions.append(chat.id)
                    onPick()
                } label: {
                    Text(chat.title + " · " + chat.provider.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }.loggedControl(control: "claude_chat_list.button_18", label: "Ativar controle")
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
                LoggedTextField("Nome", text: $title).loggedField(control: "claudechatlist.text_1", label: "Nome")
                LoggedButton("Cancelar", role: .cancel) {}.loggedControl(control: "claude_chat_list.button_19", label: "Cancelar")
                LoggedButton("Renomear") { claude.rename(chat.id, to: title) }.loggedControl(control: "claude_chat_list.button_20", label: "Renomear")
            }
            .onChange(of: chat?.id) { title = chat?.title ?? "" }
    }
}

extension View {
    func renameChatAlert(_ chat: Binding<ClaudeChat?>) -> some View {
        modifier(RenameChatAlert(chat: chat))
    }
}
