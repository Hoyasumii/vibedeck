import SwiftUI
import VibeDeckCore

struct RuleTopicView: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let slug: String
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var claude
    @Environment(\.undoManager) private var undo
    @State private var showChecks = true

    private var topic: RuleTopic { model.topic(slug) ?? RuleTopic(title: slug) }
    private var hasAnyTest: Bool { topic.rules.contains { $0.test != nil } }
    private var pendingTests: Int { RuleTestPrompt.pending(topic).count }
    private var scriptCount: Int { topic.rules.filter { $0.testState == .script }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let execution = model.ruleExecution, execution.scope.contains(slug) {
                RuleExecutionPanel(execution: execution).id(execution.id)
            }
            RuleListEditor(
                rules: topic.rules,
                emptyTitle: "Nenhuma regra ainda",
                emptyHint: "Descreva comportamentos que este tópico deve ter. Ex.: \"Nunca usar minWidth no root da janela\".",
                quickAddShortcut: true,
                testRuns: model.testRuns
            ) { action, change in
                model.mutateTopic(slug, action, undo: undo) { change(&$0.rules) }
            }
        }
        .inspector(isPresented: $showChecks) {
            ChecksList(slug: slug, checks: model.checks(forTopic: slug), rules: topic.rules)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .navigationTitle(topic.title)
        .navigationSubtitle("\(topic.rules.count) regra(s) · \(topic.isGlobal ? "vale para toda tarefa" : "\(topic.paths.count) escopo(s)")")
        .toolbar {
            ToolbarItemGroup {
                if !AIProvider.installed(in: providerRoot).isEmpty { discoverButton; testsMenu }
                RuleExecutionControls(topic: slug)
            }
            ToolbarItem {
                LoggedButton { showChecks.toggle() } label: { Label("Verificações", systemImage: "checkmark.seal") }.loggedControl(control: "rules_view.button_1", label: "Verificações")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar verificações (⌥⌘I)")
            }
        }
    }

    /// "Descubra": globs, an interview that drafts rules, then description and tags; each accept is one undo step.
    private var discoverButton: some View {
        RuleDiscoverButton(
            subject: .init(topic: topic),
            current: { .init(topic: topic) },
            vocabulary: model.tagVocabulary,
            topics: model.knownTopics(excluding: slug),
            store: model.store,
            applyScope: { scope, paths in
                model.mutateTopic(slug, "Descubra: globs", undo: undo) { scope.apply(paths: paths, tags: [], to: &$0.paths, tags: &$0.tags) }
            },
            applyRules: { drafts, chosen in
                model.mutateTopic(slug, "Descubra: regras", undo: undo) { drafts.apply(chosen, to: &$0.rules) }
            },
            applyDetails: { proposal, accepted, tags in
                model.mutateTopic(slug, "Descubra: descrição e tags", undo: undo) { proposal.apply(acceptDescription: accepted, tags: tags, description: &$0.description, tags: &$0.tags) }
            },
            applyVerdict: { _ in }
        )
        .id(slug)
    }

    /// "Gerar testes" asks Claude (in the chat) to turn each rule into a script; afterwards checks run the scripts.
    @ViewBuilder
    private var testsMenu: some View {
        if model.generatingTests[slug]?.isActive == true {
            // A background batch (Regras → Gerar verificações) is on this topic: don't start a second one.
            Label("Gerando testes…", systemImage: "hammer")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .help("As verificações deste tópico estão sendo geradas em segundo plano")
        } else {
            chatTestsMenu
        }
    }

    private var chatTestsMenu: some View {
        Menu {
            LoggedButton("Só as pendentes (\(pendingTests))") { generateTests(onlyPending: true) }.loggedControl(control: "rules_view.button_2", label: "Ativar controle")
                .disabled(pendingTests == 0)
            LoggedButton("Regenerar todas") { generateTests(onlyPending: false) }.loggedControl(control: "rules_view.button_3", label: "Regenerar todas")
        } label: {
            Label(hasAnyTest ? "Atualizar testes" : "Gerar testes", systemImage: "hammer")
        } primaryAction: {
            generateTests(onlyPending: hasAnyTest && pendingTests > 0)
        }
        .disabled(topic.rules.isEmpty || model.ruleExecution?.active == true)
        .badge(hasAnyTest ? pendingTests : 0)
        .help(hasAnyTest
            ? "Pedir ao Claude para criar os testes das regras novas ou alteradas (\(pendingTests) pendente(s))"
            : "Pedir ao Claude para transformar as regras em scripts: a verificação passa a rodá-los em vez de perguntar a ele")
    }

    private func generateTests(onlyPending: Bool) {
        claude.ask(RuleTestPrompt.generate(slug: slug, topic: topic, onlyPending: onlyPending))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                CommitTextField(control: "rulesview.field_1", "Tópico", value: topic.title) { title in
                    guard !title.isEmpty else { return }
                    model.mutateTopic(slug, "Renomear tópico", undo: undo) { $0.title = title }
                }
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                if topic.author == .ai {
                    Label("Criado por IA", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.purple)
                }
                CommitTextField(control: "rulesview.field_2", "Quando este tópico se aplica…", value: topic.description ?? "") { text in
                    model.mutateTopic(slug, "Editar descrição", undo: undo) { $0.description = text.isEmpty ? nil : text }
                }
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: topic.isGlobal ? "globe" : "scope")
                    .foregroundStyle(.secondary)
                    .help(topic.isGlobal ? "Sem escopo: vale para toda tarefa" : "Vale quando um arquivo alterado casa um destes globs")
                CommitTextField(control: "rulesview.field_3", "Escopo: globs separados por vírgula (vazio = vale para tudo)", value: topic.paths.joined(separator: ", ")) { text in
                    let paths = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    model.mutateTopic(slug, "Editar escopo", undo: undo) { $0.paths = paths }
                }
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)

            TagsField(tags: topic.tags) { tags in model.mutateTopic(slug, "Editar tags", undo: undo) { $0.tags = tags } }

            if let source = topic.sourceIdea, let idea = model.ideas.first(where: { $0.value.id == source }) {
                Label("Veio da ideia \"\(idea.value.title)\"", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let source = topic.sourcePattern, let pattern = model.project.patterns.first(where: { $0.id == source }) {
                Label("Regras do padrão de projeto \"\(pattern.name)\"; apagar o tópico retira o padrão", systemImage: "building.columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Rule list (shared by topics and ideas)

struct RuleListEditor: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let rules: [Rule]
    let emptyTitle: String
    let emptyHint: String
    var quickAddShortcut = false
    /// Last script outcome per rule, shown next to it (topics only).
    var testRuns: [UUID: RuleTestOutcome] = [:]
    let mutate: (String, @escaping (inout [Rule]) -> Void) -> Void

    private struct MovingRuleGroup: Identifiable { var path: String; var id: String { path } }
    @State private var movingRuleGroup: MovingRuleGroup?
    @State private var groupError: String?
    @State private var movingRule: Rule?
    @State private var collapsedRuleGroups = Set<String>()
    @State private var newText = ""
    @State private var newSeverity: RuleSeverity = .must
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        Group {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "checkmark.shield")
                } description: {
                    Text(emptyHint)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ruleBranch("")

                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) { quickAdd }
        .sheet(item: $movingRule) { rule in
            NamePromptSheet(title: "Mover regra para grupo", placeholder: "Grupo/subgrupo") { name in
                let storePath = name
                guard let group = try? ProjectStore(root: URL(fileURLWithPath: "/")).normalizedGroupPath(storePath, allowRoot: true) else { return }
                update(rule.id, "Mover regra") { $0.group = group.isEmpty ? nil : group }
            }
        }
        .sheet(item: $movingRuleGroup) { p in
            NamePromptSheet(title: "Mover ou renomear grupo de regras", placeholder: "Novo caminho grupo/subgrupo") { destination in
                do {
                    let store = ProjectStore(root: logProject ?? URL(fileURLWithPath: "/"))
                    let updated = try store.ruleGroupRenamed(rules, from: p.path, to: destination)
                    mutate("Mover grupo de regras") { $0 = updated }
                } catch { groupError = error.localizedDescription }
            }
        }
        .alert("Grupo inválido", isPresented: Binding(get: { groupError != nil }, set: { if !$0 { groupError = nil } })) {
            LoggedButton("OK") { groupError = nil }.loggedControl(control: "rules_view.group_error", label: "OK")
        } message: { Text(groupError ?? "") }

    }

    private var ruleGroups: [String] {
        var result = Set<String>()
        for rule in rules {
            let parts = (rule.group ?? "").split(separator: "/")
            for count in 1...max(1, parts.count) where count <= parts.count { result.insert(parts.prefix(count).joined(separator: "/")) }
        }
        return result.sorted()
    }

    private func ruleBranch(_ parent: String) -> AnyView {
        AnyView(Group {
            ForEach(ruleGroups.filter { ProjectStore.groupPath(of: $0) == parent }, id: \.self) { group in
                DisclosureGroup(isExpanded: Binding(get: { !collapsedRuleGroups.contains(group) }, set: { if $0 { collapsedRuleGroups.remove(group) } else { collapsedRuleGroups.insert(group) } })) {
                    ruleBranch(group)
                } label: { Label(String(group.split(separator: "/").last ?? ""), systemImage: "folder") }
                .contextMenu {
                    LoggedButton("Mover ou renomear grupo…") { movingRuleGroup = .init(path: group) }.loggedControl(control: "rules_view.move_rule_group", label: "Mover grupo de regras")
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard ids.count == 1, let id = UUID(uuidString: ids[0]), rules.contains(where: { $0.id == id }) else { return false }
                    update(id, "Mover regra") { $0.group = group }; return true
                }
            }
            ForEach(rules.filter { ($0.group ?? "") == parent }) { rule in
                RuleRow(rule: rule, lastRun: testRuns[rule.id]) { action, change in update(rule.id, action, change) }
                    .draggable(rule.id.uuidString)
                    .contextMenu { contextMenu(for: rule) }
            }
            .onMove { from, to in
                mutate("Reordenar regras") { rules in
                    var subset = rules.filter { ($0.group ?? "") == parent }
                    subset.move(fromOffsets: from, toOffset: to)
                    var iterator = subset.makeIterator()
                    for i in rules.indices where (rules[i].group ?? "") == parent { rules[i] = iterator.next()! }
                }
            }
            .onDelete { offsets in
                let subset = rules.filter { ($0.group ?? "") == parent }
                let ids = Set(offsets.map { subset[$0].id })
                mutate("Remover regra") { $0.removeAll { ids.contains($0.id) } }
            }
        })
    }

    private func update(_ id: Rule.ID, _ action: String, _ change: @escaping (inout Rule) -> Void) {
        mutate(action) { rules in
            guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
            change(&rules[i])
        }
    }

    @ViewBuilder
    private func contextMenu(for rule: Rule) -> some View {
        Picker("Severidade", selection: Binding(get: { rule.severity }, set: { s in update(rule.id, "Alterar severidade") { $0.severity = s } }).logging(control: "rules_view.selection_11", label: "Severidade", project: logProject)) {
            ForEach(RuleSeverity.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Menu("Mover para") {
            LoggedButton("Raiz") { update(rule.id, "Mover regra") { $0.group = nil } }.loggedControl(control: "rules_view.move_root", label: "Mover regra para raiz")
            ForEach(ruleGroups, id: \.self) { group in
                LoggedButton(group) { update(rule.id, "Mover regra") { $0.group = group } }.loggedControl(control: "rules_view.move_existing_group", label: "Mover regra para grupo")
            }
        }
        LoggedButton("Mover para grupo…") { movingRule = rule }.loggedControl(control: "rules_view.move_group", label: "Mover para grupo")
        LoggedButton("Copiar id") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rule.id.uuidString, forType: .string)
        }.loggedControl(control: "rules_view.button_4", label: "Copiar id")
        if let command = rule.test?.command {
            LoggedButton("Copiar comando do teste") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }.loggedControl(control: "rules_view.button_5", label: "Copiar comando do teste")
        }
        if rule.test != nil {
            LoggedButton("Remover teste") { update(rule.id, "Remover teste") { $0.test = nil } }.loggedControl(control: "rules_view.button_6", label: "Remover teste")
        }
        Divider()
        LoggedButton("Remover", role: .destructive) { mutate("Remover regra") { $0.removeAll { $0.id == rule.id } } }.loggedControl(control: "rules_view.button_7", label: "Remover")
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Severidade", selection: $newSeverity.logging(control: "rules_view.selection_12", label: "Severidade", project: logProject)) {
                    ForEach(RuleSeverity.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: newSeverity.symbol)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help(newSeverity.label)

            LoggedTextField("Nova regra…", text: $newText, onCommit: add).loggedField(control: "rulesview.text_1", label: "Nova regra…")
                .textFieldStyle(.plain)
                .focused($quickAddFocused)


            LoggedButton(action: add) { Image(systemName: "plus") }.loggedControl(control: "rules_view.button_8", label: "Ativar controle")
                .buttonStyle(.glassProminent)
                .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background {
            if quickAddShortcut {
                LoggedButton("") { quickAddFocused = true }.loggedControl(control: "rules_view.button_9", label: "").keyboardShortcut("n", modifiers: [.command, .shift]).hidden()
            }
        }
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let rule = Rule(text: text, severity: newSeverity)
        mutate("Adicionar regra") { $0.append(rule) }
        newText = ""
    }
}

extension RuleSeverity {
    var symbol: String { self == .must ? "exclamationmark.shield.fill" : "shield" }
}

struct RuleRow: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let rule: Rule
    var lastRun: RuleTestOutcome?
    let update: (String, @escaping (inout Rule) -> Void) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LoggedButton {
                update("Alterar severidade") { $0.severity = $0.severity == .must ? .should : .must }
            } label: {
                Image(systemName: rule.severity.symbol)
                    .foregroundStyle(rule.severity == .must ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .font(.title3)
            }.loggedControl(control: "rules_view.button_10", label: "Ativar controle")
            .buttonStyle(.plain)
            .help("\(rule.severity.label) — clique para alternar")

            VStack(alignment: .leading, spacing: 3) {
                CommitTextField(control: "rulesview.field_4", "Regra", value: rule.text) { v in
                    guard !v.isEmpty else { return }
                    update("Editar regra") { $0.text = v }
                }
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))

                CommitTextField(control: "rulesview.field_5", "Como verificar (opcional)…", value: rule.details ?? "", axis: .vertical) { v in
                    update("Editar detalhes") { $0.details = v.isEmpty ? nil : v }
                }
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)

                HStack(spacing: 6) {
                    Text(rule.severity.label)
                        .font(.caption.weight(.medium))
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .glassEffect(.regular.tint((rule.severity == .must ? Color.orange : Color.gray).opacity(0.3)), in: .capsule)
                    if rule.testState != .none { TestChip(rule: rule, lastRun: lastRun) }
                    Text(rule.id.uuidString.prefix(8)).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                    if rule.author == .ai {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple).help("Criada por IA")
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

/// How the rule is verified (script / manual / stale) and, for scripts, the last run in this session.
private struct TestChip: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let rule: Rule
    let lastRun: RuleTestOutcome?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(rule.testState.label)
            if rule.testState == .script, let lastRun {
                Image(systemName: lastRun.verdict.symbol).foregroundStyle(lastRun.verdict.color)
            }
        }
        .font(.caption.weight(.medium))
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 2)
        .glassEffect(.regular.tint(tint.opacity(0.3)), in: .capsule)
        .help(help)
    }

    private var symbol: String {
        switch rule.testState {
        case .script: "gearshape"
        case .manual: "hand.raised"
        case .stale, .none: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch rule.testState {
        case .script: .blue
        case .manual: .gray
        case .stale, .none: .orange
        }
    }

    private var help: String {
        var lines: [String] = []
        switch rule.testState {
        case .script: lines.append("Verificada pelo script: \(rule.test?.command ?? "")")
        case .manual: lines.append("Não testável por script: o agente verifica no check.")
        case .stale: lines.append("A regra mudou depois do teste: volta a ser manual até você atualizar os testes.")
        case .none: break
        }
        if let reason = rule.test?.reason { lines.append(reason) }
        if rule.testState == .script, let lastRun {
            lines.append("Última execução: exit \(lastRun.exitCode)\n\(lastRun.output.suffix(600))")
        }
        return lines.joined(separator: "\n")
    }
}

extension RuleVerdict {
    var symbol: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .na: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .pass: .green
        case .fail: .red
        case .na: .secondary
        }
    }
}

// MARK: - Checks

struct ChecksList: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let slug: String
    let checks: [RuleCheck]
    let rules: [Rule]

    var body: some View {
        if checks.isEmpty {
            ContentUnavailableView("Nenhuma verificação", systemImage: "checkmark.seal",
                                   description: Text("Agentes registram verificações com submit_rule_check (MCP) ou `vibedeck rules check`."))
        } else {
            List {
                Section("Verificações recentes") {
                    ForEach(checks) { check in
                        DisclosureGroup {
                            ForEach(check.results.filter { $0.topic == slug }, id: \.ruleId) { result in
                                ResultRow(result: result, text: rules.first { $0.id == result.ruleId }?.text)
                            }
                        } label: {
                            CheckLabel(check: check)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct CheckLabel: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let check: RuleCheck

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: check.passed ? (check.warnings.isEmpty ? "checkmark.seal.fill" : "checkmark.seal") : "xmark.seal.fill")
                .foregroundStyle(check.passed ? (check.warnings.isEmpty ? Color.green : Color.yellow) : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.task.isEmpty ? "Sem descrição" : check.task).lineLimit(2)
                HStack(spacing: 4) {
                    Text(check.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if check.author == .ai { Image(systemName: "sparkles").foregroundStyle(.purple) }
                    if check.reviewItem != nil { Image(systemName: "checklist").help("Ligado a um item de revisão") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ResultRow: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let result: RuleResult
    let text: String?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: result.verdict.symbol).foregroundStyle(result.verdict.color)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(text ?? "Regra removida").font(.callout).foregroundStyle(text == nil ? .secondary : .primary)
                    if result.source == .script {
                        Image(systemName: "gearshape").font(.caption).foregroundStyle(.secondary).help("Decidida pelo script da regra")
                    }
                }
                if let note = result.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(6) }
            }
        }
    }
}
