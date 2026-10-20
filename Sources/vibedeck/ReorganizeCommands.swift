import ArgumentParser
import Foundation
import VibeDeckCore

struct Reorganize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reorganize",
        abstract: "Propõe organização com IA; só aplica ações com aceite explícito.",
        subcommands: [Prompt.self, Analyze.self, Validate.self, Apply.self])
    struct Prompt: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Exporta prompt, schema e fingerprint sem gravar.")
        @OptionGroup var options: RootOptions
        func run() throws {
            let store = try ProjectStore.locate(from: options.startURL)
            try printJSON(["prompt": ReorganizeDiscover.prompt(store: store), "schema": ReorganizeDiscover.schema,
                           "fingerprint": store.reorganizeFingerprint()])
        }
    }
    struct Analyze: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Analisa com provedor somente leitura; saída é uma proposta JSON.")
        @OptionGroup var options: RootOptions
        @Option(help: "claude ou codex; escolha explícita.") var provider: String
        @Option(help: "Modelo do provedor.") var model: String?
        @Option(help: "Esforço do modelo.") var effort: String?
        func run() async throws {
            guard let provider = AIProvider(rawValue: provider) else { throw ValidationError("Use claude ou codex.") }
            try printJSON(await ReorganizeDiscover.analyze(store: ProjectStore.locate(from: options.startURL),
                provider: provider, settings: .init(model: model, effort: effort)))
        }
    }
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Converte resposta JSON em proposta validada, sem gravar.")
        @OptionGroup var options: RootOptions
        @Option(help: "JSON da resposta da IA; - lê stdin.") var file: String
        @Option(help: "Fingerprint fornecido por prompt.") var fingerprint: String
        func run() throws {
            let data = file == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: URL(fileURLWithPath: file))
            try printJSON(ReorganizeDiscover.parse(data, store: ProjectStore.locate(from: options.startURL), fingerprint: fingerprint))
        }
    }
    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Aplica somente IDs aceitos; conflitos precisam de escolha explícita.")
        @OptionGroup var options: RootOptions
        @Option(help: "Arquivo JSON da proposta validada.") var file: String
        @Option(help: "JSON de aceite: selected (IDs) e conflicts (ID da ação -> chave do item mantido).") var acceptance: String
        func run() throws {
            let proposal = try ReorganizeDiscover.decodeProposal( Data(contentsOf: URL(fileURLWithPath: file)))
            let accepted = try ReorganizeDiscover.decodeAcceptance( Data(contentsOf: URL(fileURLWithPath: acceptance)))
            let receipt = try ProjectStore.locate(from: options.startURL).applyReorganization(proposal, acceptance: accepted)
            try printJSON(receipt)
        }
    }
}
