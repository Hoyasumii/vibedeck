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
                .markdownTheme(.basic)
                .markdownImageProvider(MarkdownImageProvider())
                .markdownInlineImageProvider(MarkdownInlineImageProvider())
                .textSelection(.enabled)
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Loads markdown images through `NSImage`, local or remote. MarkdownUI's default loaders only decode
/// what CGImageSource does, so SVGs (e.g. the Skill Icons badge) and `file://` attachments never showed.
@MainActor
enum MarkdownImageLoader {
    struct LoadError: Error {}

    private static let cache = NSCache<NSURL, NSImage>()

    static func cached(_ url: URL) -> NSImage? { cache.object(forKey: url.absoluteURL as NSURL) }

    static func image(at url: URL) async throws -> NSImage {
        let key = url.absoluteURL as NSURL
        if let image = cache.object(forKey: key) { return image }
        let image: NSImage?
        if url.isFileURL {
            image = NSImage(contentsOf: url)
        } else {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LoadError() }
            image = NSImage(data: data)
        }
        guard let image, image.isValid else { throw LoadError() }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Block images (alone in their paragraph).
private struct MarkdownImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        MarkdownImage(url: url)
    }
}

private struct MarkdownImage: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width)
            } else if failed || url == nil {
                Label(url?.lastPathComponent ?? "Imagem", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = MarkdownImageLoader.cached(url)
            failed = false
            guard image == nil else { return }
            do { image = try await MarkdownImageLoader.image(at: url) } catch { failed = true }
        }
    }
}

/// Images that share a paragraph with anything else (text, another image, a line break) are inline.
private struct MarkdownInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        Image(nsImage: try await MarkdownImageLoader.image(at: url))
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
