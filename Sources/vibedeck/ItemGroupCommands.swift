import ArgumentParser
import Foundation
import VibeDeckCore

extension ItemConcept: ExpressibleByArgument {}

struct ItemGroups: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "groups", abstract: "Diretórios de ideias, revisões, docs e skills; regras dentro de tópicos.", subcommands: [List.self, Create.self, Move.self, Rename.self, Remove.self, MoveItem.self, MoveRule.self, RenameRules.self])
    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Flag var json = false
        func run() throws {
            let groups = try options.store().listItemDirectories(concept)
            if json { try printJSON(groups) } else { groups.forEach { print($0.path) } }
        }
    }
    struct Create: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Argument var path: String
        func run() throws { print(try options.store().createItemDirectory(concept, path: path)) }
    }
    struct Move: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Argument var from: String
        @Argument var to: String
        func run() throws { try options.store().moveItemDirectory(concept, from: from, to: to); print("Grupo movido.") }
    }
    struct Rename: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Argument var path: String
        @Argument var name: String
        func run() throws {
            let store = try options.store()
            guard !name.contains("/") else { throw VibeDeckError.invalidGroupPath(name) }
            let parent = ProjectStore.groupPath(of: path)
            try store.moveItemDirectory(concept, from: path, to: (parent.isEmpty ? "" : parent + "/") + name)
            print("Grupo renomeado.")
        }
    }
    struct Remove: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Argument var path: String
        @Flag(help: "Confirma apagar todos os itens do grupo, inclusive de autoria humana.") var confirmed = false
        func run() throws { try options.store().deleteItemDirectory(concept, path: path, confirmed: confirmed); print("Grupo apagado.") }
    }
    struct MoveItem: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var concept: ItemConcept
        @Argument var reference: String
        @Argument(help: "Grupo de destino; string vazia para a raiz.") var group: String
        func run() throws { print(try options.store().moveGroupedItem(concept, reference: reference, to: group)) }
    }
    struct MoveRule: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var rule: String
        @Argument var group: String
        func run() throws { _ = try options.store().moveRuleToGroup(rule, group: group); print("Regra movida.") }
    }
    struct RenameRules: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var topic: String
        @Argument var from: String
        @Argument var to: String
        func run() throws { try options.store().renameRuleGroup(topic: topic, from: from, to: to); print("Grupo de regras movido.") }
    }
}
