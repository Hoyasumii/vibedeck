import AppKit
import MarkdownUI
import SwiftUI

/// Rendered markdown of a doc or idea. Relative links/images (`../attachments/…`) resolve against `baseURL`.
struct MarkdownPreview: View {
    let text: String
    let baseURL: URL

    var body: some View {
        ScrollView {
            Markdown(text, baseURL: baseURL)
                .markdownTheme(.gitHub)
                .markdownImageProvider(LocalImageProvider())
                .textSelection(.enabled)
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Loads `file://` images straight from disk; anything else goes through MarkdownUI's network loader.
private struct LocalImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let url, url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width)
            } else {
                Label(url.lastPathComponent, systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        } else {
            DefaultImageProvider.default.makeImage(url: url)
        }
    }
}

/// Editar / Dividir / Ler, shared by docs and ideas.
enum MarkdownViewMode: String, CaseIterable {
    case edit, split, read
    var label: String { ["edit": "Editar", "split": "Dividir", "read": "Ler"][rawValue]! }
    var symbol: String { ["edit": "pencil", "split": "rectangle.split.2x1", "read": "book"][rawValue]! }
}

/// Toolbar segmented picker for `MarkdownViewMode`; pair it with `markdownModeShortcut` on the content.
struct MarkdownModePicker: View {
    @Binding var mode: MarkdownViewMode

    var body: some View {
        Picker("Modo", selection: $mode) {
            ForEach(MarkdownViewMode.allCases, id: \.self) { m in
                Label(m.label, systemImage: m.symbol).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .help("Editar / Dividir / Ler (⌘E alterna)")
    }
}

extension View {
    /// ⌘E toggles between editing and reading.
    func markdownModeShortcut(_ mode: Binding<MarkdownViewMode>) -> some View {
        background {
            Button("") { mode.wrappedValue = mode.wrappedValue == .read ? .edit : .read }
                .keyboardShortcut("e")
                .hidden()
        }
    }
}

/// Toolbar button that picks files to attach; `onPick` copies them and returns the markdown to insert.
struct AttachButton: View {
    let onPick: ([URL]) -> Void
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: { Label("Anexar", systemImage: "paperclip") }
            .help("Anexar arquivos (copiados para .vibedeck/attachments). Também dá para arrastar ou colar no texto.")
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result, !urls.isEmpty { onPick(urls) }
            }
    }
}
