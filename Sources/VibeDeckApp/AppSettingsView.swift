import SwiftUI
import VibeDeckCore

/// App settings (⌘,). Preferences of this machine, kept in UserDefaults: never in vibedeck.json nor in .vibedeck/.
struct AppSettingsView: View {
    /// Shows activeProcessorCount while nothing is stored; the stepper only accepts 1...activeProcessorCount.
    @AppStorage(RuleExecutionModel.concurrencyKey) private var concurrency = ProjectStore.defaultScriptConcurrency

    var body: some View {
        Form {
            Section("Regras") {
                Stepper(value: $concurrency.logging(control: "app_settings_view.concurrency", label: "Scripts ao mesmo tempo"),
                        in: 1...ProjectStore.defaultScriptConcurrency) {
                    LabeledContent("Scripts ao mesmo tempo", value: "\(ProjectStore.scriptConcurrency(concurrency))")
                }
                Text("Quantos scripts de regras rodam em paralelo ao executar as regras no app (máximo: \(ProjectStore.defaultScriptConcurrency), o número de núcleos desta máquina). Scripts que usam a mesma ferramenta de build (swift, npm, cargo, gradle…) continuam rodando um por vez. O CLI e o MCP sempre usam o padrão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
