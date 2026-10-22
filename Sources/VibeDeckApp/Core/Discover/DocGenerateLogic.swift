import Foundation

/// Proposta de documento do repositório. Prompt, schema, validação e gravação são do Core
/// (`doc_generate_prompt` / `doc_generate_validate` / `doc_generate_apply`, ver CoreStore+DocGenerate.swift);
/// aqui só vive o valor editado na folha de revisão. Editar ou descartar nunca grava no projeto.
enum DocGenerate {
    struct Document: Equatable, Identifiable, Sendable {
        var title: String
        var content: String
        var id = UUID()
        /// Destino local escolhido no app; nunca vem da resposta da IA.
        var group: String? = nil

        init(title: String, content: String) {
            self.title = title
            self.content = content
        }

        /// Título e conteúdo preenchidos e dentro do limite informado pelo Core (`maxContentLength`).
        func isAcceptable(maxContentLength: Int) -> Bool {
            let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !content.isEmpty && content.count <= maxContentLength
        }
    }
}
