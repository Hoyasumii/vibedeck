import SwiftUI

/// Início guiado (pranchas 31 a 34, MUD-001): 1. Stack, 2. Padrões, 3. Recursos encontrados, 4. Resumo.
/// Nada é gravado antes de "Concluir" no resumo; "Pular por agora" guarda o estado e pode ser retomado em
/// Projeto › Visão geral.
struct V2OnboardingSheet: View {
    let report: OnboardingReport
    let onFinished: () -> Void

    @Environment(ProjectModel.self) private var model
    @State private var step = 0
    @State private var stack: [StackItem] = []
    @State private var pickingStack = false
    @State private var catalog: [PatternCatalogEntry] = []
    @State private var catalogFailure: String?
    @State private var chosenPatterns = Set<String>()
    @State private var chosenResources = Set<String>()
    @State private var applying = false
    @State private var failure: String?

    private let titles = ["Stack", "Padrões", "Recursos encontrados", "Resumo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .interactiveDismissDisabled(true)
        .task { await start() }
        .sheet(isPresented: $pickingStack) {
            StackPicker(current: stack) { stack = $0 }
        }
    }

    private func start() async {
        stack = model.project.stack
        do {
            catalog = try await model.store.patternCatalog()
        } catch {
            catalogFailure = error.localizedDescription
        }
    }

    // MARK: Cabeçalho e rodapé

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text("Início guiado").font(DesignTokens.Typography.displayLG)
            HStack(spacing: DesignTokens.Space.s2) {
                ForEach(0..<titles.count, id: \.self) { index in
                    VDBadge("\(index + 1). \(titles[index])", tone: index == step ? .brand : .neutral)
                }
            }
        }
        .padding(DesignTokens.Space.s6)
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            LoggedButton("Pular por agora") { skip() }
                .loggedControl(control: "v2_onboarding.skip", label: "Pular por agora")
                .buttonStyle(VDButtonStyle(kind: .quiet, size: .md))
                .disabled(applying)
            if let failure {
                Text(failure)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.fix)
                    .lineLimit(2)
            }
            Spacer()
            if step > 0 {
                LoggedButton("Voltar") { step -= 1 }
                    .loggedControl(control: "v2_onboarding.back", label: "Voltar")
                    .buttonStyle(VDButtonStyle(kind: .secondary, size: .md))
                    .disabled(applying)
            }
            if step < titles.count - 1 {
                LoggedButton("Continuar") { step += 1 }
                    .loggedControl(control: "v2_onboarding.next", label: "Continuar")
                    .buttonStyle(VDButtonStyle(kind: .primary, size: .md))
            } else {
                LoggedButton(applying ? "Gravando…" : "Concluir") { finish() }
                    .loggedControl(control: "v2_onboarding.finish", label: "Concluir")
                    .buttonStyle(VDButtonStyle(kind: .primary, size: .md))
                    .disabled(applying)
            }
        }
        .padding(DesignTokens.Space.s4)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: stackStep
        case 1: patternsStep
        case 2: resourcesStep
        default: summaryStep
        }
    }

    // MARK: 1. Stack (prancha 31)

    private var stackStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text("Quais tecnologias o projeto usa?").font(DesignTokens.Typography.title)
            Text("A IA lê a stack antes de implementar qualquer coisa. Só o que você marcar entra.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
            if stack.isEmpty {
                Text("Nenhuma tecnologia escolhida.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DesignTokens.Space.s2, alignment: .leading)],
                          alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(stack) { item in VDBadge(item.name, tone: .neutral) }
                }
            }
            LoggedButton("Escolher tecnologias") { pickingStack = true }
                .loggedControl(control: "v2_onboarding.pick_stack", label: "Escolher tecnologias")
                .buttonStyle(VDButtonStyle(kind: .secondary, size: .md))
            Spacer()
        }
        .padding(DesignTokens.Space.s6)
    }

    // MARK: 2. Padrões (prancha 32)

    private var patternsStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text("Quais padrões de projeto vocês seguem?").font(DesignTokens.Typography.title)
            Text("Cada padrão escolhido gera um tópico de regras com escopo.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
            if let catalogFailure {
                Text(catalogFailure).font(DesignTokens.Typography.callout).foregroundStyle(DesignTokens.Colors.fix)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(catalog) { entry in patternRow(entry) }
                }
            }
        }
        .padding(DesignTokens.Space.s6)
    }

    private func patternRow(_ entry: PatternCatalogEntry) -> some View {
        let adopted = entry.inProject
        let isOn = chosenPatterns.contains(entry.id)
        return LoggedButton {
            if isOn { chosenPatterns.remove(entry.id) } else { chosenPatterns.insert(entry.id) }
        } label: {
            checkRow(title: entry.name, subtitle: entry.summary, marked: isOn || adopted,
                     badge: adopted ? "já adotado" : nil)
        }
        .loggedControl(control: "v2_onboarding.pattern", label: entry.name)
        .buttonStyle(.plain)
        .disabled(adopted)
    }

    // MARK: 3. Recursos encontrados (prancha 33)

    private var resourcesStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text("Recursos encontrados no projeto").font(DesignTokens.Typography.title)
            Text("Skills, agentes e comandos que já existem em .claude e .codex. Nada é importado sem marcação.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
            if report.resources.isEmpty {
                Text("Nenhum recurso encontrado.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(report.resources) { resource in resourceRow(resource) }
                }
            }
        }
        .padding(DesignTokens.Space.s6)
    }

    private func resourceRow(_ resource: OnboardingReport.Resource) -> some View {
        let isOn = chosenResources.contains(resource.id)
        return LoggedButton {
            if isOn { chosenResources.remove(resource.id) } else { chosenResources.insert(resource.id) }
        } label: {
            checkRow(title: resource.name, subtitle: resource.kindLabel + " · " + resource.origin,
                     marked: isOn || resource.registered, badge: resource.registered ? "já cadastrado" : nil)
        }
        .loggedControl(control: "v2_onboarding.resource", label: resource.name)
        .buttonStyle(.plain)
        .disabled(resource.registered)
    }

    private func checkRow(title: String, subtitle: String, marked: Bool, badge: String?) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s3) {
            Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(marked ? DesignTokens.Colors.brandText : DesignTokens.Colors.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DesignTokens.Typography.headline).foregroundStyle(DesignTokens.Colors.ink)
                Text(subtitle)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
                    .lineLimit(2)
            }
            Spacer()
            if let badge { VDBadge(badge, tone: .neutral) }
        }
        .padding(DesignTokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface100)
        )
        .contentShape(Rectangle())
    }

    // MARK: 4. Resumo (prancha 34)

    private var newStack: [StackItem] {
        stack.filter { item in !model.project.stack.contains { $0.icon == item.icon } }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text("Resumo").font(DesignTokens.Typography.title)
            Text("Só ao concluir os registros são criados, como feitos por você.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
            summaryLine("Stack", newStack.map(\.name))
            summaryLine("Padrões", chosenPatterns.sorted())
            summaryLine("Recursos", chosenResources.sorted())
            Spacer()
        }
        .padding(DesignTokens.Space.s6)
    }

    private func summaryLine(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
            Text("\(title) (\(values.count))").font(DesignTokens.Typography.headline)
            Text(values.isEmpty ? "Nada novo." : values.joined(separator: ", "))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
        }
    }

    // MARK: Ações

    private func skip() {
        Task {
            do {
                try await model.store.onboardingSkip()
                onFinished()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Padrões e recursos vão pelo Core; depois a memória relê o projeto e só então a stack é gravada, para a
    /// gravação do projeto inteiro não apagar os padrões novos.
    private func finish() {
        applying = true
        failure = nil
        let patterns = chosenPatterns.sorted()
        let resources = chosenResources.sorted()
        let chosenStack = stack
        let hasStackChange = !newStack.isEmpty || chosenStack.count != model.project.stack.count
        Task {
            do {
                if !patterns.isEmpty { _ = try await model.store.addPatterns(patterns, note: nil, paths: []) }
                if !resources.isEmpty {
                    let outcome = try await model.store.onboardingImport(resources)
                    if !outcome.warnings.isEmpty { failure = outcome.warnings.joined(separator: "\n") }
                }
                await model.refresh(.project)
                if hasStackChange {
                    model.mutateStack("Início guiado: stack", undo: nil) { $0 = chosenStack }  // undo agrupado: o assistente confirma tudo em "Concluir"
                }
                try await model.store.onboardingComplete()
                model.reloadAll()
                applying = false
                onFinished()
            } catch {
                applying = false
                failure = error.localizedDescription
            }
        }
    }
}
