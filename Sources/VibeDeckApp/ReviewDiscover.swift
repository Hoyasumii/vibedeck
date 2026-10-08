import SwiftUI
import VibeDeckCore

/// Runs one "Descubra" call for a review item: a read-only `claude -p` with a timeout that can be cancelled.
/// The answer only becomes a proposal; the inspector applies it after the user accepts.
@Observable @MainActor
final class ReviewDiscoverRunner {
    enum State: Equatable {
        case idle, running
        case failed(String)
        case ready(ReviewDiscoverProposal)
    }

    var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { state == .running }

    func start(item: ReviewItem, kind: String, topics: [(slug: String, topic: RuleTopic)], store: ProjectStore) {
        guard let executable = ClaudeCode.executable else { return }
        cancel()
        state = .running
        let prompt = ReviewDiscover.prompt(item: item, kind: kind, topics: ReviewDiscover.candidateTopics(topics, item: item))
        task = Task {
            do {
                let output = try await Self.run(executable: executable, root: store.root, input: prompt)
                let answer = try ReviewDiscover.parse(output)
                guard !Task.isCancelled else { return }
                state = .ready(ReviewDiscover.proposal(answer, item: item, topics: topics, store: store))
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .running { state = .idle }
    }

    /// The item was edited while the call ran: the answer would be based on stale data.
    func itemChanged() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        state = .failed("O item mudou durante a busca; nada foi alterado. Rode o Descubra de novo.")
    }

    func dismiss() {
        if !isRunning { state = .idle }
    }

    // MARK: Process

    /// stdout of the call. Terminates the process on cancellation and after `ReviewDiscover.timeout`.
    private nonisolated static func run(executable: URL, root: URL, input: String) async throws -> Data {
        let path = ClaudeCode.childPATH()
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = ReviewDiscover.arguments()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { throw VibeDeckError.discoverFailed(error.localizedDescription) }
        try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let timedOut = Task.detached {
            try? await Task.sleep(for: ReviewDiscover.timeout)
            guard !Task.isCancelled, process.isRunning else { return false }
            process.terminate()
            return true
        }
        defer { timedOut.cancel() }
        let output = await withTaskCancellationHandler {
            await Task.detached {
                // Drain stderr concurrently so a chatty hook can't fill the pipe and block the process.
                let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                _ = await errors.value
                process.waitUntilExit()
                return data
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        timedOut.cancel()
        if await timedOut.value { throw VibeDeckError.discoverTimedOut }
        return output
    }
}

/// The proposal: each suggestion with its reason and a checkbox. Replacing a filled field starts unchecked.
struct ReviewDiscoverSheet: View {
    let proposal: ReviewDiscoverProposal
    let apply: (Set<ReviewDiscover.Field>, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fields: Set<ReviewDiscover.Field> = []
    @State private var topics: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if proposal.isEmpty {
                    Text("O Claude não encontrou nada novo para este item.").foregroundStyle(.secondary)
                }
                if !proposal.fields.isEmpty {
                    Section("Onde") {
                        ForEach(proposal.fields) { change in
                            Toggle(isOn: member(change.field, in: $fields)) {
                                Text("\(change.field.label): \(change.suggested)")
                                if let current = change.current {
                                    Text("Substitui: \(current)").font(.caption).foregroundStyle(.orange)
                                }
                                if let reason = change.reason { Text(reason).font(.caption) }
                            }
                        }
                    }
                }
                if !proposal.topics.isEmpty {
                    Section {
                        ForEach(proposal.topics) { topic in
                            Toggle(isOn: member(topic.slug, in: $topics)) {
                                Text(topic.title)
                                if let reason = topic.reason { Text(reason).font(.caption) }
                            }
                        }
                    } header: {
                        Text("Regras")
                    } footer: {
                        Text("O Descubra só adiciona tópicos; os que já estão ligados continuam.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !proposal.discarded.isEmpty {
                    Section("Descartado") {
                        ForEach(proposal.discarded, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Aplicar selecionados") {
                    apply(fields, topics)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fields.isEmpty && topics.isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
        .navigationTitle("Descubra")
        .onAppear {
            fields = proposal.defaultFields
            topics = Set(proposal.topics.map(\.slug))
        }
    }

    private func member<T: Hashable>(_ value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(value) }, set: { on in
            if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
        })
    }
}
