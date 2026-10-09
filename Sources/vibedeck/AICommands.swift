import ArgumentParser
import Foundation
import VibeDeckCore

struct AI: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ai", abstract: "Documentação, contexto e consumo local de IA.",
        subcommands: [Guide.self, Context.self, Catalog.self, Usage.self])
    struct Guide: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Índice do guia; leia uma seção por vez.")
        @Option(help: "Número da seção no índice.") var section: Int?
        @Flag(help: "Saída JSON.") var json = false
        func run() throws {
            guard let section else { if json { try printJSON(AgentsGuide.index) } else { print(AgentsGuide.index) }; return }
            guard let text = AgentsGuide.section(section) else { throw ValidationError("Seção inexistente.") }
            if json { try printJSON(text) } else { print(text) }
        }
    }
    struct Context: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lê uma página de contexto local, sem perder o restante.")
        @OptionGroup var options: RootOptions
        @Argument(help: "Identificador da referência.") var id: String
        @Flag(help: "Saída JSON com próxima posição.") var json = false
        @Option var offset: Int = 0
        @Option var limit: Int = 4000
        func run() throws {
            let page = try AIContextStore(root: options.store().root).page(id: id, offset: offset, limit: limit)
            if json { try printJSON(page) } else {
                print(page.text)
                if let next = page.nextOffset { print("\nContinuação: --offset \(next) (total: \(page.totalCharacters) caracteres)") }
            }
        }
    }
    struct Catalog: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lista registros sem carregar prompts; JSON paginado.")
        @OptionGroup var options: RootOptions
        @Argument(help: "agents, commands, skills, workflows ou rules.") var kind: String
        @Flag(help: "Saída JSON.") var json = false
        @Option var offset: Int = 0
        @Option var limit: Int = 20
        func run() throws {
            let page = try options.store().aiCatalog(kind: kind, offset: offset, limit: limit)
            if json { try printJSON(page) } else {
                for item in page.items { print("\(item.ref): \(item.title)\(item.summary.map { " — " + $0 } ?? "")") }
                if let next = page.nextOffset { print("Continuação: --offset \(next)") }
            }
        }
    }
    struct Usage: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Consumo local por tarefa; dados ausentes são não informados.")
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false
        @Flag(help: "Apaga somente as métricas locais deste projeto.") var clear = false
        func run() throws {
            let store = AIUsageStore(root: try options.store().root)
            if clear { try store.clear(); return }
            let records = try store.list()
            if json { try printJSON(records); return }
            for r in records {
                print("\(r.operation) · \(r.provider.title) · \(r.model ?? "modelo não informado") · tarefa \(r.taskID) · tentativa \(r.attempt) · entrada \(r.tokens.input.map(String.init) ?? "não informada") · saída \(r.tokens.output.map(String.init) ?? "não informada") · \(r.status)")
            }
        }
    }
}
