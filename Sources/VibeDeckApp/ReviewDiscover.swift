import SwiftUI

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

    func start(item: ReviewItem, kind: String, topics: [(slug: String, topic: RuleTopic)], store: CoreStore, provider: AIProvider = .claude) {
        guard RemoteExecution.available(provider, root: store.root) else { state = .failed("\(provider.title) não está instalado."); return }
        cancel()
        state = .running
        let prompt = ReviewDiscover.prompt(item: item, kind: kind, topics: ReviewDiscover.candidateTopics(topics, item: item))
        task = Task {
            do {
                let answer = try await AIReadOnlyOperation.run(root: store.root, provider: provider,
                    operation: "Descubra", prompt: prompt, schema: ReviewDiscover.schema) { data in
                    let value = try JSONDecoder().decode(JSONValue.self, from: data)
                    guard value["fields"]?.array != nil, value["rules"]?.array != nil else { throw VibeDeckError.discoverInvalidAnswer }
                    let answer = try JSONDecoder().decode(ReviewDiscover.Answer.self, from: data)
                    let proposal = ReviewDiscover.proposal(answer, item: item, topics: topics, store: store)
                    guard proposal.discarded.isEmpty,
                          answer.fields.allSatisfy({ !($0.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                          answer.rules.allSatisfy({ !($0.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
                    return answer
                }
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
}

/// The proposal: each suggestion with its reason and a checkbox. Replacing a filled field starts unchecked.
struct ReviewDiscoverSheet: View {
    @Environment(\.logProject) private var logProject
    let proposal: ReviewDiscoverProposal
    let apply: (Set<ReviewDiscover.Field>, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fields: Set<ReviewDiscover.Field> = []
    @State private var topics: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if proposal.isEmpty {
                    Text("A IA não encontrou nada novo para este item.").foregroundStyle(.secondary)
                }
                if !proposal.fields.isEmpty {
                    Section("Onde") {
                        ForEach(proposal.fields) { change in
                            Toggle(isOn: member(change.field, in: $fields).logging(control: "review_discover.selection_3", label: "Alternar", project: logProject)) {
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
                            Toggle(isOn: member(topic.slug, in: $topics).logging(control: "review_discover.selection_4", label: "Alternar", project: logProject)) {
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
                LoggedButton("Cancelar", role: .cancel) { dismiss() }.loggedControl(control: "review_discover.button_1", label: "Cancelar")
                    .keyboardShortcut(.cancelAction)
                LoggedButton("Aplicar selecionados") {
                    apply(fields, topics)
                    dismiss()
                }.loggedControl(control: "review_discover.button_2", label: "Aplicar selecionados")
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
