import SwiftUI
import VibeDeckCore

struct WelcomeView: View {
    @Binding var root: URL?
    @State private var pendingInit: URL?
    @State private var projectName = ""
    @State private var errorMessage: String?
    private var recents: RecentProjects { .shared }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                Text("VibeDeck").font(.largeTitle.weight(.semibold))
                Text("Links, docs e pontos de revisão dos seus projetos — em arquivos que a IA também lê.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if let url = FolderPicker.pick() { open(url) }
            } label: {
                Label("Abrir pasta…", systemImage: "folder")
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            if !recents.urls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recentes").font(.headline).padding(.leading, 6)
                    GlassEffectContainer(spacing: 4) {
                        VStack(spacing: 4) {
                            ForEach(recents.urls, id: \.self) { url in
                                Button { open(url) } label: {
                                    HStack {
                                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                                        VStack(alignment: .leading) {
                                            Text(url.lastPathComponent)
                                            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                .contextMenu { Button("Remover dos recentes") { recents.remove(url) } }
                            }
                        }
                    }
                }
                .frame(maxWidth: 440)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.hasDirectoryPath else { return false }
            open(url)
            return true
        }
        .sheet(item: $pendingInit) { url in
            InitProjectSheet(url: url, name: $projectName) {
                do {
                    try ProjectStore.initialize(at: url, name: projectName)
                    pendingInit = nil
                    root = url
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Erro", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func open(_ url: URL) {
        if ProjectStore.isProject(url) {
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
            TextField("Nome do projeto", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button("Inicializar projeto", action: onCreate)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
