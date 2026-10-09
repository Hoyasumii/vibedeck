import SwiftUI
import VibeDeckCore

struct AIUsageHistoryView: View {
    let root: URL
    @State private var records: [AIUsageRecord] = []
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Consumo de IA neste projeto").font(.headline)
                Spacer()
                Button("Limpar métricas", role: .destructive) {
                    do { try AIUsageStore(root: root).clear(); reload() }
                    catch { errorMessage = error.localizedDescription }
                }.disabled(records.isEmpty)
                Button("Fechar") { dismiss() }
            }
            Text("Tokens informados pelo provedor. Chamadas externas podem não estar incluídas. Caracteres medem a entrada da tarefa, sem instruções de sistema e leituras posteriores.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if records.isEmpty { ContentUnavailableView("Sem consumo registrado", systemImage: "chart.bar", description: Text("As próximas tarefas aparecerão aqui.")) }
            List {
                ForEach(AIUsageTask.group(records)) { task in
                    Section {
                        ForEach(task.records) { record in usageRow(record) }
                    } header: {
                        VStack(alignment: .leading) {
                            Text("Tarefa \(task.id)")
                            Text("\(task.records.count) chamada(s) · entrada \(count(task.total(\.input))) · saída \(count(task.total(\.output))) · \(task.duration, specifier: "%.1f") s somados")
                        }
                    }
                }
            }
        }
        .padding().frame(minWidth: 620, minHeight: 360)
        .task {
            while !Task.isCancelled {
                reload()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private func usageRow(_ record: AIUsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(record.operation) · \(record.provider.title) · \(record.model.flatMap { $0.isEmpty ? nil : $0 } ?? "modelo não informado")")
            Text("Entrada: \(count(record.tokens.input)) · Saída: \(count(record.tokens.output)) · Cache lido: \(count(record.tokens.cachedInput)) · Cache gravado: \(count(record.tokens.cacheWrite))")
                .font(.caption).monospacedDigit()
            Text("Tentativa \(record.attempt) · \(record.duration, specifier: "%.1f") s · \(record.promptCharacters) caracteres na tarefa · \(status(record.status))")
                .font(.caption).foregroundStyle(.secondary)
            Text("Tarefa: \(record.taskID)").font(.caption2).foregroundStyle(.secondary)
            if record.coverage.hasPrefix("partial") { Text("Cobertura parcial: conversa retomada sem contador inicial.").font(.caption).foregroundStyle(.secondary) }
            if let cost = record.costUSD { Text("Custo informado: US$ \(cost, specifier: "%.4f")").font(.caption) }
        }
        .textSelection(.enabled)
    }
    private func count(_ value: Int?) -> String { value.map(String.init) ?? "não informado" }
    private func status(_ value: String) -> String {
        switch value {
        case "completed": "Concluída"
        case "cancelled": "Cancelada"
        case "failed": "Falhou"
        case "invalid-answer": "Resposta inválida"
        default: "Em andamento"
        }
    }
    private func reload() {
        do { records = try AIUsageStore(root: root).list(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
