import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct LinksView: View {
    @Environment(\.logProject) private var logProject
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.openURL) private var openURL
    @State private var selection = Set<ProjectLink.ID>()
    @State private var viewing: ProjectLink?
    @State private var editing: ProjectLink?
    @State private var claudeEditing: ClaudeItem?
    @State private var search = ""

    private var links: [ProjectLink] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.project.links }
        return model.project.links.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.url.localizedCaseInsensitiveContains(q)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        HSplitView {
            Group {
                if model.project.links.isEmpty {
                    ContentUnavailableView {
                        Label("Sem links", systemImage: "link")
                    } description: {
                        Text("Adicione com + ou cole uma URL (⌘V).")
                    } actions: {
                        LoggedButton("Adicionar link") { editing = ProjectLink(title: "", url: "") }.loggedControl(control: "links_view.button_1", label: "Adicionar link").buttonStyle(.glass)
                    }
                } else {
                    Table(links, selection: $selection.logging(control: "links_view.selection_11", label: "Seleção", project: logProject)) {
                        TableColumn("Título") { link in
                            Text(link.title).fontWeight(.medium)
                        }
                        TableColumn("URL") { link in
                            Text(link.url).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        TableColumn("Tags") { link in
                            TagChips(tags: link.tags)
                        }
                        .width(min: 80, ideal: 160)
                    }
                    .contextMenu(forSelectionType: ProjectLink.ID.self) { ids in
                        if let id = ids.first, let link = model.project.links.first(where: { $0.id == id }) {
                            LoggedButton("Abrir") { open(link) }.loggedControl(control: "links_view.button_2", label: "Abrir")
                            LoggedButton("Abrir no navegador") {
                                if let url = URL(string: link.url) { openURL(url) }
                            }.loggedControl(control: "links_view.open_in_browser", label: "Abrir no navegador")
                            LoggedButton("Copiar URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.url, forType: .string) }.loggedControl(control: "links_view.button_3", label: "Copiar URL")
                            LoggedButton("Editar…") { editing = link }.loggedControl(control: "links_view.button_4", label: "Editar…")
                            Divider()
                        }
                        LoggedButton("Remover", role: .destructive) { remove(ids) }.loggedControl(control: "links_view.button_5", label: "Remover")
                    } primaryAction: { ids in
                        ids.compactMap { id in model.project.links.first { $0.id == id } }.forEach(open)
                    }
                    .onDeleteCommand { remove(selection) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let viewing {
                LinkViewerPanel(link: viewing) { self.viewing = nil }
                    .id(viewing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Links")
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrar links")
        .toolbar {
            ToolbarItem {
                LoggedButton {
                    claudeEditing = ClaudeItem(title: "", url: "", kind: .artifact)
                } label: { Label("Adicionar do Claude", systemImage: "square.stack.badge.plus") }.loggedControl(control: "links_view.button_6", label: "Adicionar do Claude")
            }
            ToolbarItem {
                LoggedButton { editing = ProjectLink(title: "", url: "") } label: { Label("Novo link", systemImage: "plus") }.loggedControl(control: "links_view.button_7", label: "Novo link")
            }
        }
        .onPasteCommand(of: [.url, .plainText]) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let text = (string as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return }
                    Task { @MainActor in
                        if ClaudeItem.accepts(text) {
                            claudeEditing = ClaudeItem(title: ClaudeItem.suggestedTitle(for: text), url: text, kind: .artifact)
                        } else {
                            add(ProjectLink(title: url.host() ?? text, url: text))
                        }
                    }
                }
            }
        }
        .sheet(item: $claudeEditing) { item in
            ClaudeItemEditor(item: item, isNew: true) { saved in
                model.mutateProject("Adicionar do Claude", undo: undo) { $0.claude.append(saved) }
            }
        }
        .sheet(item: $editing) { link in
            LinkEditor(link: link, isNew: !model.project.links.contains(where: { $0.id == link.id })) { saved in
                if model.project.links.contains(where: { $0.id == saved.id }) {
                    model.mutateProject("Editar link", undo: undo) { p in
                        if let i = p.links.firstIndex(where: { $0.id == saved.id }) { p.links[i] = saved }
                    }
                } else {
                    add(saved)
                }
            }
        }
    }

    private func open(_ link: ProjectLink) {
        viewing = link
    }

    private func add(_ link: ProjectLink) {
        model.mutateProject("Adicionar link", undo: undo) { $0.links.append(link) }
    }

    private func remove(_ ids: Set<ProjectLink.ID>) {
        guard !ids.isEmpty else { return }
        model.mutateProject("Remover link", undo: undo) { $0.links.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
    }
}


private struct LinkViewerPanel: View {
    @Environment(\.openURL) private var openURL
    let link: ProjectLink
    let close: () -> Void
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(link.title).font(.headline).lineLimit(1)
                Spacer()
                LoggedButton("Abrir no navegador") {
                    if let url = URL(string: link.url) { openURL(url) }
                }
                .loggedControl(control: "links_view.viewer_open_in_browser", label: "Abrir no navegador")
                .help("Abrir no navegador padrão")
                LoggedButton("Fechar", action: close)
                    .loggedControl(control: "links_view.viewer_close", label: "Fechar")
                    .help("Fechar visualizador de links")
            }
            .padding()
            Divider()
            ZStack {
                if let url = URL(string: link.url), LinkViewerNavigation.permits(url) {
                    LinkWebView(url: url, isLoading: $isLoading, failed: $failed)
                    if failed {
                        ContentUnavailableView("Não foi possível carregar a página", systemImage: "exclamationmark.triangle",
                                               description: Text("Tente abrir o link no navegador."))
                    } else if isLoading {
                        ProgressView("Carregando página…").padding().background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
                } else {
                    ContentUnavailableView("Link não compatível", systemImage: "link.badge.plus",
                                           description: Text("O visualizador aceita apenas URLs http e https."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The original request and its redirects stay embedded; page navigation leaves the viewer.
enum LinkViewerNavigation {
    enum Decision: Equatable { case allow, cancel, external }

    static func permits(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    static func decision(url: URL?, currentURL: URL?, type: WKNavigationType,
                         isMainFrame: Bool?, opensWindow: Bool = false) -> Decision {
        guard let url else { return .cancel }
        if opensWindow || isMainFrame == nil {
            return permits(url) ? .external : .cancel
        }
        // Frames are part of rendering the page; only top-level navigation leaves the viewer.
        if isMainFrame == false { return .allow }
        guard permits(url) else { return .cancel }
        if type == .formSubmitted || (type == .linkActivated && url != currentURL) { return .external }
        return .allow
    }
}

private struct LinkWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard LinkViewerNavigation.permits(url), context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: LinkWebView
        var loaded: URL?
        init(parent: LinkWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            switch LinkViewerNavigation.decision(url: action.request.url, currentURL: webView.url ?? loaded,
                                                  type: action.navigationType, isMainFrame: action.targetFrame?.isMainFrame) {
            case .allow: return .allow
            case .cancel: return .cancel
            case .external:
                if let url = action.request.url { NSWorkspace.shared.open(url) }
                return .cancel
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if LinkViewerNavigation.decision(url: action.request.url, currentURL: webView.url ?? loaded,
                                             type: action.navigationType, isMainFrame: action.targetFrame?.isMainFrame,
                                             opensWindow: true) == .external, let url = action.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.failed = false
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.isLoading = false
            parent.failed = true
        }

        private func fail(_ error: Error) {
            // Cancelling a navigation to open it externally is not a page-load failure.
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.isLoading = false
            parent.failed = true
        }
    }
}

struct TagChips: View {
    @Environment(\.logProject) private var logProject
    let tags: [String]
    /// When set, chips are clickable (e.g. to filter by that tag).
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .glassEffect(onTap == nil ? .regular : .regular.interactive(), in: .capsule)
                        .onTapGesture { VDLog.withAction(control: "links_view.tap_15", label: "Selecionar", project: logProject) { onTap?(tag) } }
                        .help(onTap == nil ? "" : "Filtrar por #\(tag)")
                }
            }
        }
    }
}

/// Comma-separated tag editor in a glass capsule; commits on submit/blur.
struct TagsField: View {
    @Environment(\.logProject) private var logProject
    let tags: [String]
    let onCommit: ([String]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "number").foregroundStyle(.secondary)
            CommitTextField(control: "linksview.field_1", "tags, separadas, por vírgula", value: tags.joined(separator: ", ")) { text in
                onCommit(Tags.parse(text))
            }
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .frame(minWidth: 180, maxWidth: 360)
    }
}

enum Tags {
    static func parse(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Creating a link confirms with "Criar"; editing one writes each field (and an undo step) on Return
/// or when it loses focus, like the rest of the app.
private struct LinkEditor: View {
    @Environment(\.logProject) private var logProject
    @State var link: ProjectLink
    let isNew: Bool
    let onSave: (ProjectLink) -> Void
    @State private var tagsText = ""
    /// Last value written, so Return and focus loss don't record empty undo steps.
    @State private var original: ProjectLink?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            LoggedTextField("URL", text: $link.url, onCommit: commit).loggedField(control: "linksview.text_1", label: "URL")
            LoggedTextField("Título", text: $link.title, onCommit: commit).loggedField(control: "linksview.text_2", label: "Título")
            LoggedTextField("Tags (separadas por vírgula)", text: $tagsText, onCommit: commit).loggedField(control: "linksview.text_3", label: "Tags (separadas por vírgula)")
        }
        .focused($focused)
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            tagsText = link.tags.joined(separator: ", ")
            original = normalized
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { LoggedButton("Cancelar") { dismiss() }.loggedControl(control: "links_view.button_8", label: "Cancelar") }
                ToolbarItem(placement: .confirmationAction) {
                    LoggedButton("Criar") { onSave(normalized); dismiss() }.loggedControl(control: "links_view.button_9", label: "Criar")
                        .disabled(link.url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    LoggedButton("Concluído") { commit(); dismiss() }.loggedControl(control: "links_view.button_10", label: "Concluído")
                }
            }
        }
    }

    private var normalized: ProjectLink {
        var saved = link
        saved.url = saved.url.trimmingCharacters(in: .whitespaces)
        if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
            saved.title = URL(string: saved.url)?.host() ?? saved.url
        }
        saved.tags = Tags.parse(tagsText)
        return saved
    }

    /// Writes the edit in place; a no-op while creating, or when nothing changed or the URL is empty.
    private func commit() {
        guard !isNew, !link.url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let saved = normalized
        guard saved != original else { return }
        original = saved
        onSave(saved)
    }
}
