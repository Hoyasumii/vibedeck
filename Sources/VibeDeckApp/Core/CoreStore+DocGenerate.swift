import Foundation

// Geração de documentos e recuperação de IA: o prompt, o schema, a validação e a gravação vêm do Core
// (tools `doc_generate_*`, `ai_recovery_prompt`, `link_doc`); a execução da IA continua no app.

/// Resposta de `doc_generate_prompt`.
struct DocGeneratePlan: Decodable, Equatable, Sendable {
    var prompt: String
    var schema: String
    var maxDocuments: Int
    var maxContentLength: Int
}

/// Resposta de `ai_recovery_prompt`.
struct AIRecoveryPlan: Decodable, Equatable, Sendable {
    var prompt: String
    var incomplete: String
}

extension CoreStore {
    func docGeneratePlan() async throws -> DocGeneratePlan {
        try await callJSON("doc_generate_prompt", idempotent: true)
    }

    /// Valida a resposta da IA no Core e devolve as propostas aceitáveis (não grava).
    func docGenerateValidate(answer: Data) async throws -> [DocGenerate.Document] {
        struct Row: Decodable { var title: String; var content: String }
        let text: String
        do {
            text = try await call("doc_generate_validate", ["answer": String(decoding: answer, as: UTF8.self)], idempotent: true)
        } catch let error as CoreError {
            throw VibeDeckError.docGenerationInvalidAnswer.wrapping(error)
        }
        let rows = try CoreStore.decode([Row].self, from: text, what: "doc_generate_validate")
        return rows.map { DocGenerate.Document(title: $0.title, content: $0.content) }
    }

    /// Cria os documentos aceitos (author=ai), tudo ou nada; devolve os slugs.
    func docGenerateApply(_ documents: [DocGenerate.Document], group: String) async throws -> [String] {
        let rows: [[String: Any]] = documents.map { document in
            var row: [String: Any] = ["title": document.title, "content": document.content]
            if let group = document.group, !group.isEmpty { row["group"] = group }
            return row
        }
        return try await callJSON("doc_generate_apply", ["documents": rows, "group": group])
    }

    func aiRecoveryPrompt(original: String, diagnosis: String) async throws -> AIRecoveryPlan {
        try await callJSON("ai_recovery_prompt", ["original": original, "diagnosis": diagnosis], idempotent: true)
    }

    /// Re-vincula um .md da raiz (`Vinculado: <slug>`); devolve o slug.
    @discardableResult
    func linkDoc(file: String) async throws -> String {
        let reply = try await call("link_doc", ["file": file])
        let prefix = "Vinculado: "
        guard reply.hasPrefix(prefix) else { throw CoreError.protocolError("link_doc: \(reply)") }
        return String(reply.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
