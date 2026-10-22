import SwiftUI

struct WelcomeView: View {
    @Binding var root: URL?
    @State private var sshSheet = false
    @State private var pendingInit: URL?
    @State private var projectName = ""
    @State private var errorMessage: String?
    private var recents: RecentProjects { .shared }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("VibeDeck").font(.largeTitle.weight(.semibold))
                Text("Links, docs e pontos de revisão dos seus projetos — em arquivos que a IA também lê.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            LoggedButton {
                if let url = FolderPicker.pick() { open(url) }
            } label: {
                Label("Abrir pasta…", systemImage: "folder")
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }.loggedControl(control: "welcome_view.button_1", label: "Abrir pasta…")
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            LoggedButton("Conectar via SSH…") { sshSheet = true }
                .loggedControl(control: "welcome.ssh", label: "Conectar via SSH")
                .buttonStyle(.glass)

            if !recents.urls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recentes").font(.headline).padding(.leading, 6)
                    GlassEffectContainer(spacing: 4) {
                        VStack(spacing: 4) {
                            ForEach(recents.urls, id: \.self) { url in
                                LoggedButton { open(url) } label: {
                                    HStack {
                                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                                        VStack(alignment: .leading) {
                                            Text(RemoteWorkspace.existing(at: url)?.destination.title ?? url.lastPathComponent)
                                            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .contentShape(.rect)
                                }.loggedControl(control: "welcome_view.button_2", label: "Ativar controle")
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                .contextMenu { LoggedButton("Remover dos recentes") { recents.remove(url) }.loggedControl(control: "welcome_view.button_3", label: "Remover dos recentes") }
                            }
                        }
                    }
                }
                .frame(maxWidth: 440)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the window background run under the title bar instead of a separate toolbar strip.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.hasDirectoryPath else { return false }
            open(url)
            return true
        }
        .sheet(isPresented: $sshSheet) { SSHProjectSheet { root = $0 } }
        .sheet(item: $pendingInit) { url in
            InitProjectSheet(url: url, name: $projectName) {
                let name = projectName
                Task {
                    do {
                        try await CoreStore.initializeProject(at: url, name: name)
                        pendingInit = nil
                        root = url
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        // A folder that arrived through ⌘O / onOpenURL / the Dock but isn't a project yet: offer to initialize it.
        .onAppear { if let root { open(root) } }
        .alert("Erro", isPresented: .constant(errorMessage != nil)) {
            LoggedButton("OK") { errorMessage = nil }.loggedControl(control: "welcome_view.button_4", label: "OK")
        } message: { Text(errorMessage ?? "") }
    }

    private func open(_ url: URL) {
        if CoreStore.isProject(url) {
            root = url
        } else {
            projectName = url.lastPathComponent
            pendingInit = url
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct InitProjectSheet: View {
    let url: URL
    @Binding var name: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Nenhum projeto VibeDeck nesta pasta", systemImage: "questionmark.folder")
                .font(.headline)
            Text("Criar **vibedeck.json** e a pasta **.vibedeck/** em\n\(url.path(percentEncoded: false))")
                .foregroundStyle(.secondary)
            LoggedTextField("Nome do projeto", text: $name).loggedField(control: "welcomeview.text_1", label: "Nome do projeto")
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                LoggedButton("Cancelar", role: .cancel) { dismiss() }.loggedControl(control: "welcome_view.button_5", label: "Cancelar")
                    .buttonStyle(.glass)
                LoggedButton("Inicializar projeto", action: onCreate).loggedControl(control: "welcome_view.button_6", label: "Inicializar projeto")
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
