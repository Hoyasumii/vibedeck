import SwiftUI
import WebKit
import VibeDeckCore

/// Runs `graphify update .` (AST-only, no AI cost) for one project, one run at a time.
/// The previous `graphify-out/` stays untouched unless the run succeeds.
@MainActor @Observable
final class GraphRunner {
    enum State: Equatable { case idle, running, failed(String) }
    private(set) var state = State.idle
    private(set) var generation = 0
    private var process: Process?
    private var cancelled = false

    func start(root: URL) {
        guard state != .running else { return }
        state = .running
        cancelled = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", "graphify update ."]
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ClaudeCode.childPATH()
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] proc in
            let tail = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile().suffix(1500), as: UTF8.self)
            Task { @MainActor in self?.finish(status: proc.terminationStatus, output: tail) }
        }
        do { try process.run(); self.process = process }
        catch { state = .failed("Não foi possível executar o graphify: \(error.localizedDescription)") }
    }

    func cancel() { cancelled = true; process?.terminate() }

    private func finish(status: Int32, output: String) {
        process = nil
        if cancelled { state = .idle; return }
        if status == 0 { generation += 1; state = .idle; return }
        let notFound = status == 127
        state = .failed(notFound ? "graphify não encontrado. Instale-o (pip install graphifyy) e tente de novo."
                                 : output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct GraphView: View {
    @Environment(ProjectModel.self) private var model
    @State private var runner = GraphRunner()
    @State private var reload = 0

    private var out: URL { model.store.root.appending(path: "graphify-out") }
    private var html: URL { out.appending(path: "graph.html") }
    private var json: URL { out.appending(path: "graph.json") }

    private var summary: String? {
        _ = reload; _ = runner.generation
        guard let graph = try? ProjectGraph.load(root: model.store.root) else { return nil }
        let when = (try? json.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { " · gerado em " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        return "\(graph.nodes.count) nós · \(graph.links.count) relações" + when
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            if case .failed(let message) = runner.state {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.bar)
            }
        }
        .navigationTitle("Grafo")
        .toolbar {
            ToolbarItem {
                if runner.state == .running {
                    Button("Cancelar", systemImage: "xmark.circle") { runner.cancel() }
                } else {
                    Button("Atualizar", systemImage: "arrow.clockwise") { runner.start(root: model.store.root) }
                        .help("Executa `graphify update .` (estrutura do código, sem IA)")
                }
            }
            ToolbarItem { if runner.state == .running { ProgressView().controlSize(.small) } }
            ToolbarItem { if let summary { Text(summary).font(.caption).foregroundStyle(.secondary) } }
        }
    }

    @ViewBuilder private var content: some View {
        let _ = runner.generation
        if FileManager.default.fileExists(atPath: html.path) {
            GraphWebView(file: html, readAccess: out, reload: runner.generation + reload)
        } else if runner.state == .running {
            ProgressView("Gerando grafo…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if FileManager.default.fileExists(atPath: json.path) {
            ContentUnavailableView {
                Label("Sem visualização HTML", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text("Existe graphify-out/graph.json, mas não graph.html. Atualize para gerar a visualização.")
            } actions: {
                Button("Atualizar") { runner.start(root: model.store.root) }.buttonStyle(.glass)
            }
        } else {
            ContentUnavailableView {
                Label("Sem grafo", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text("Gere o grafo do projeto com o graphify. Nada é executado até você pedir.")
            } actions: {
                Button("Gerar grafo") { runner.start(root: model.store.root) }.buttonStyle(.glass)
            }
        }
    }
}

/// Shows the graphify HTML with read access limited to `graphify-out/` and no way out of the page:
/// external navigation is cancelled and opened in the default browser instead.
private struct GraphWebView: NSViewRepresentable {
    let file: URL
    let readAccess: URL
    let reload: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != reload || view.url == nil else { return }
        context.coordinator.loaded = reload
        view.loadFileURL(file, allowingReadAccessTo: readAccess)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = -1
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.isFileURL || url.scheme == "about" || action.navigationType == .other && action.targetFrame?.isMainFrame != true { return .allow }
            if action.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}
