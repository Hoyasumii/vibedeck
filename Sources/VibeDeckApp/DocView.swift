import SwiftUI

struct DocView: View {
    let slug: String
    @Environment(ProjectModel.self) private var model
    @State private var editingAction: String?
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var conflict: String?
    @State private var insertion: MarkdownInsertion?
    @State private var confirmingUnlink = false
    @AppStorage("docViewMode") private var mode: MarkdownViewMode = .edit

    private var isDirty: Bool { text != savedText }

    /// Registro do doc na lista (traz o vínculo com o Markdown da raiz, se houver).
    private var info: DocInfo? { model.docs.first { $0.slug == slug } }

    var body: some View {
        content
            .navigationTitle(model.docs.first { $0.slug == slug }?.title ?? slug)
            .navigationSubtitle(isDirty ? "Editando…" : "Salvo")
            .toolbar {
                ToolbarItem { AttachButton(onPick: attach) }
                ToolbarItem { MarkdownModePicker(mode: $mode) }
            }
            .markdownModeShortcut($mode)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    linkBanner
                    if let conflict {
                        ConflictBanner {
                            text = conflict
                            savedText = conflict
                            self.conflict = nil
                        } keep: {
                            self.conflict = nil
                            save()
                        }
                    }
                }
            }
            .confirmationDialog("Remover o vínculo?", isPresented: $confirmingUnlink) {
                LoggedButton("Remover vínculo", role: .destructive) { model.deleteDoc(slug) }
                    .loggedControl(control: "doc_view.unlink_confirm", label: "Remover vínculo")
            } message: {
                Text("Só o link em Docs é removido. \(info?.link?.target ?? "O arquivo") continua na raiz do projeto.")
            }
            .task(id: info?.isBroken == true) { await load() }
            .onChange(of: text) { _, _ in saveIfNeeded() }
            .onChange(of: model.externalDocChange[slug]) { _, _ in handleExternalChange() }
            .onDisappear(perform: flush)
            .onReceive(NotificationCenter.default.publisher(for: .vibedeckFlushPendingSaves)) { _ in flush() }
    }

    // MARK: Doc vinculado (MUD-002, pranchas 35 e 36)

    /// Selo "Vinculado" com a origem. Editar grava na origem (o link simbólico aponta para o arquivo da raiz).
    @ViewBuilder
    private var linkBanner: some View {
        if let link = info?.link, !link.broken {
            HStack(spacing: DesignTokens.Space.s3) {
                VDBadge("Vinculado", icon: .link, tone: .brand)
                Text("Origem: \(link.target). Editar grava na origem.")
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
                    .lineLimit(1)
                Spacer()
                LoggedButton("Remover vínculo") { confirmingUnlink = true }
                    .loggedControl(control: "doc_view.unlink", label: "Remover vínculo")
                    .buttonStyle(VDButtonStyle(kind: .secondary, size: .md))
                    .disabled(model.isReadOnly)
            }
            .padding(.horizontal, DesignTokens.Space.s4)
            .padding(.vertical, DesignTokens.Space.s2)
        }
    }

    /// Vínculo quebrado: a origem sumiu. Não há texto para abrir; só dá para remover o vínculo.
    private var brokenView: some View {
        ContentUnavailableView {
            Label("Vínculo quebrado", systemImage: "exclamationmark.triangle")
        } description: {
            Text("A origem \(info?.link?.target ?? "") não existe mais na raiz do projeto. Restaure o arquivo ou remova só o vínculo (o link em Docs).")
        } actions: {
            LoggedButton("Remover vínculo") { model.deleteDoc(slug) }
                .loggedControl(control: "doc_view.unlink_broken", label: "Remover vínculo")
                .buttonStyle(VDButtonStyle(kind: .primary, size: .md))
                .disabled(model.isReadOnly)
        }
    }

    @ViewBuilder
    private var content: some View {
        if info?.isBroken == true {
            brokenView
        } else {
            editorModes
        }
    }

    @ViewBuilder
    private var editorModes: some View {
        switch mode {
        case .edit:
            editor
        case .read:
            preview
        case .split:
            HSplitView {
                editor.frame(minWidth: 280)
                preview.frame(minWidth: 280)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $text,
            undoManager: model.undoManager(forDoc: slug),
            baseURL: model.store.docsDir,
            reference: slug,
            importFiles: { model.importAttachments($0, owner: slug) },
            importImage: { model.importAttachment(data: $0, name: "colagem-\(Date.now.formatted(.iso8601)).png", owner: slug) },
            insertion: insertion,
            onEditingAction: { editingAction = $0 }
        )
    }

    private var preview: some View {
        MarkdownPreview(text: CoreStore.markdownForGroupedRecord(text, reference: slug), baseURL: model.store.docURL(slug).deletingLastPathComponent())
    }

    /// Files from the "Anexar" button go in through the editor (so ⌘Z undoes them): at the cursor, or
    /// at the end after opening the editor beside the preview when only the preview is showing.
    private func attach(_ urls: [URL]) {
        let links = model.importAttachments(urls, owner: slug).joined(separator: "\n")
        guard !links.isEmpty else { return }
        guard mode == .read else { return insertion = MarkdownInsertion(text: links) }
        mode = .split
        DispatchQueue.main.async { insertion = MarkdownInsertion(text: links, atEnd: true) }
    }

    // MARK: Persistence

    private func load() async {
        guard !loaded, info?.isBroken != true else { return }
        let disk = await model.loadDoc(slug)
        text = disk
        savedText = disk
        loaded = true
    }

    private func saveIfNeeded() {
        guard loaded, isDirty else { return }
        save()
    }

    private func save() {
        VDLog.$actionID.withValue(VDLog.actionID ?? editingAction) {
            guard conflict == nil else { return }
            model.saveDoc(slug, text: text)
            savedText = text
        }
    }

    private func flush() {
        if isDirty { save() }
    }

    private func handleExternalChange() {
        let disk = model.readDoc(slug)
        guard disk != savedText, disk != text else { return }
        if isDirty {
            conflict = disk
        } else {
            savedText = disk
            text = disk
        }
    }
}

private struct ConflictBanner: View {
    let reload: () -> Void
    let keep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            Text("Este documento foi alterado fora do app enquanto você editava.")
            Spacer()
            LoggedButton("Recarregar do disco", action: reload).loggedControl(control: "doc_view.button_1", label: "Recarregar do disco").buttonStyle(.glass)
            LoggedButton("Manter minha versão", action: keep).loggedControl(control: "doc_view.button_2", label: "Manter minha versão").buttonStyle(.glassProminent)
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
