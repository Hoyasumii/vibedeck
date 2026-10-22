import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

@Suite struct RuleDiscoverTests {
    private let subject = RuleDiscover.Subject(
        kind: .topic, title: "Interface", description: "Telas do app", paths: ["Sources/App/Old/**"], tags: ["ui"],
        rules: [Rule(text: "Nada de minWidth no root")]
    )

    @Test func readOnlyToolsAndStrictSchemas() throws {
        #expect(RuleDiscover.tools == ["Read", "Grep", "Glob"])
        for schema in [RuleDiscover.scopeSchema, RuleDiscover.interviewSchema, RuleDiscover.detailsSchema, RuleDiscover.verdictSchema] {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(schema.utf8))
            #expect(value["type"]?.string == "object")
        }
    }

    @Test func scopeDropsCatchAllMissingAndCurrentGlobs() {
        let files = ["Sources/App/View.swift", "Sources/App/Old/A.swift", "README.md"]
        let answer = RuleDiscover.ScopeAnswer(paths: [
            .init(value: "**/*", reason: "tudo"),
            .init(value: "*", reason: "tudo"),
            .init(value: "Sources/Nope/**", reason: "x"),
            .init(value: "Sources/App/Old/**", reason: "já existe"),
            .init(value: "Sources/App/*.swift", reason: "View.swift:1"),
            .init(value: "Sources/App/*.swift", reason: "repetido"),
        ])
        let scope = RuleDiscover.scope(answer, subject: subject, vocabulary: [], files: files)
        #expect(scope.paths.map(\.glob) == ["Sources/App/*.swift"])
        #expect(scope.paths.first?.matches == 1)
        #expect(scope.paths.first?.reason == "View.swift:1")
        #expect(scope.discarded.count == 3)
        #expect(RuleDiscover.isCatchAll("**") && RuleDiscover.isCatchAll("./**/*") && !RuleDiscover.isCatchAll("*.swift"))
    }

    @Test func tagsPreferVocabularyAndNewOnesStartUnchecked() {
        let answer = RuleDiscover.ScopeAnswer(tags: [
            .init(value: "UI", reason: "já tem"),
            .init(value: "#Revisoes", reason: "x"),
            .init(value: "interface", reason: "y"),
        ])
        let scope = RuleDiscover.scope(answer, subject: subject, vocabulary: ["revisões", "ui"], files: [])
        #expect(scope.tags.map(\.tag) == ["revisões", "interface"])
        #expect(scope.tags.map(\.isNew) == [false, true])
        #expect(scope.defaultTags == ["revisões"])
    }

    @Test func scopeApplyOnlyAdds() {
        var scope = RuleDiscoverScope()
        scope.paths = [.init(glob: "a/**", matches: 1), .init(glob: "b/**", matches: 1)]
        scope.tags = [.init(tag: "x", isNew: false), .init(tag: "y", isNew: true)]
        var paths = ["old/**"], tags = ["ui"]
        scope.apply(paths: ["b/**"], tags: ["x"], to: &paths, tags: &tags)
        #expect(paths == ["old/**", "b/**"])
        #expect(tags == ["ui", "x"])
        scope.apply(paths: [], tags: [], to: &paths, tags: &tags)
        #expect(paths == ["old/**", "b/**"])
    }

    @Test func decodesProviderAnswers() throws {
        let scope = try JSONDecoder().decode(RuleDiscover.ScopeAnswer.self, from: Data(#"{"paths":[{"glob":"a/**","reason":"a:1"}],"tags":[{"tag":"ui","reason":"b"}]}"#.utf8))
        #expect(scope.paths == [.init(value: "a/**", reason: "a:1")])
        #expect(scope.tags.map(\.value) == ["ui"])
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RuleDiscover.ScopeAnswer.self, from: Data(#"{"paths":"x"}"#.utf8)) }

        let interview = try JSONDecoder().decode(RuleDiscover.InterviewAnswer.self, from: Data("""
        {"questions":[{"text":"A","options":["1","2"]},{"text":" ","options":[]},{"text":"B","options":[]},{"text":"C","options":[]},{"text":"D","options":[]},{"text":"E","options":[]}],
         "rules":[{"text":"R","details":"","severity":"should","reason":"x","related":"","relation":"none"}]}
        """.utf8))
        #expect(interview.questions.map(\.text) == ["A", "B", "C", "D"])
        #expect(interview.questions.first?.options == ["1", "2"])
        #expect(interview.rules.first?.severity == .should)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RuleDiscover.InterviewAnswer.self, from: Data(#"{"questions":[],"rules":[{"text":"R","severity":"talvez"}]}"#.utf8))
        }
    }

    @Test func draftsFlagDuplicatesAndConflicts() {
        let answer = RuleDiscover.InterviewAnswer(rules: [
            .init(text: "Nada de minWidth no root!", reason: "a"),
            .init(text: "Usar cápsula de vidro", reason: "b", related: "Sem vidro", relation: .conflict),
            .init(text: "Cada aba persiste", severity: .should, reason: "c"),
            .init(text: "cada aba persiste", reason: "repetida"),
            .init(text: "  ", reason: "vazia"),
        ])
        let topics = [RuleDiscover.KnownTopic(slug: "visual", title: "Visual", rules: ["Sem vidro"])]
        let drafts = RuleDiscover.drafts(answer, subject: subject, topics: topics)
        #expect(drafts.rules.map(\.text) == ["Nada de minWidth no root!", "Usar cápsula de vidro", "Cada aba persiste"])
        #expect(drafts.rules.map(\.relation) == [.duplicate, .conflict, .none])
        #expect(drafts.rules[0].related == "Nada de minWidth no root")
        #expect(drafts.defaultRules == [drafts.rules[2].id])

        var rules = [Rule(text: "Existente")]
        drafts.apply([drafts.rules[2].id], to: &rules)
        #expect(rules.map(\.text) == ["Existente", "Cada aba persiste"])
        #expect(rules.last?.author == .ai)
        #expect(rules.last?.severity == .should)
    }

    @Test func promptsCarryContextAndRoundLimit() {
        let topics = [RuleDiscover.KnownTopic(slug: "core", title: "Core", rules: ["Toda escrita passa por AtomicFile"])]
        let scope = RuleDiscover.scopePrompt(subject, topics: topics)
        #expect(scope.contains("Título: Interface"))
        #expect(scope.contains("Descrição: Telas do app"))
        #expect(scope.contains("Globs atuais: Sources/App/Old/**"))
        #expect(scope.contains("Toda escrita passa por AtomicFile"))

        let history = [RuleDiscover.Exchange(question: "Vale no iPad?", answer: "")]
        let asking = RuleDiscover.interviewPrompt(subject, topics: topics, history: history, finish: false)
        #expect(asking.contains("até \(RuleDiscover.maxQuestions) perguntas"))
        #expect(asking.contains("R: (sem resposta)"))
        #expect(asking.contains("[must] Nada de minWidth no root"))
        let finishing = RuleDiscover.interviewPrompt(subject, topics: topics, history: history, finish: true)
        #expect(finishing.contains("Não faça mais perguntas"))
    }

    @Test func ideaPathsRoundTripAndAreOmittedWhenEmpty() throws {
        var idea = Idea(title: "X")
        #expect(!String(decoding: try VDJSON.encode(idea), as: UTF8.self).contains("\"paths\""))
        idea.paths = ["Sources/**"]
        let decoded = try VDJSON.decoder.decode(Idea.self, from: VDJSON.encode(idea))
        #expect(decoded.paths == ["Sources/**"])
        let handWritten = try VDJSON.decoder.decode(Idea.self, from: Data(#"{"title":"Y"}"#.utf8))
        #expect(handWritten.paths.isEmpty)
    }

    @Test func reloadFromDiskIsNotAnEdit() throws {
        var topic = RuleTopic(title: "X")
        topic.rules = [Rule(text: "Nunca X", now: Date(timeIntervalSince1970: 1_000.5))]
        let reloaded = try VDJSON.decoder.decode(RuleTopic.self, from: VDJSON.encode(topic))
        let before = RuleDiscover.Subject(topic: topic), after = RuleDiscover.Subject(topic: reloaded)
        #expect(before != after)
        #expect(before.hasSameContent(as: after))
        var edited = reloaded
        edited.rules[0].text = "Nunca Y"
        #expect(!before.hasSameContent(as: RuleDiscover.Subject(topic: edited)))
    }

    @Test func promotionCopiesAndMergesIdeaPaths() throws {
        let store = try newStore()
        try AtomicFile.write(Data("x".utf8), to: store.root.appending(path: "Sources/App/View.swift"))
        let (slug, _) = try store.createIdea(title: "Ideia")
        try store.updateIdea(slug) { $0.paths = ["Sources/App/**", "Sources/Gone/**"]; $0.rules = [Rule(text: "R")] }
        #expect(try store.unmatchedIdeaPaths(slug) == ["Sources/Gone/**"])

        let topic = try store.promoteIdea(slug, skippingPaths: ["Sources/Gone/**"])
        #expect(try store.loadTopic(topic).paths == ["Sources/App/**"])

        try store.updateTopic(topic) { $0.paths.append("Tests/**") }
        try store.updateIdea(slug) { $0.paths.append("Package.swift") }
        #expect(try store.promoteIdea(slug) == topic)
        #expect(try store.loadTopic(topic).paths == ["Sources/App/**", "Tests/**", "Sources/Gone/**", "Package.swift"])
    }

    @Test func contextEntersEveryPromptOnlyWhenGiven() {
        #expect(!RuleDiscover.scopePrompt(subject, topics: []).contains("Contexto do usuário"))
        var withContext = subject
        withContext.context = "Quero modo offline só no iPhone"
        #expect(RuleDiscover.scopePrompt(withContext, topics: []).contains("Quero modo offline só no iPhone"))
        #expect(RuleDiscover.interviewPrompt(withContext, topics: [], history: [], finish: false).contains("Quero modo offline só no iPhone"))
        #expect(RuleDiscover.detailsPrompt(withContext, vocabulary: [], topics: [], history: []).contains("Quero modo offline só no iPhone"))
    }

    @Test func scopeAsksOnlyForGlobs() throws {
        #expect(!RuleDiscover.scopeSchema.contains("tags"))
        #expect(!RuleDiscover.scopePrompt(subject, topics: []).contains("- tags:"))
        let answer = try JSONDecoder().decode(RuleDiscover.ScopeAnswer.self, from: Data(#"{"paths":[{"glob":"a/**","reason":"a:1"}]}"#.utf8))
        #expect(answer.tags.isEmpty)
    }

    @Test func detailsPromptAndProposal() throws {
        let history = [RuleDiscover.Exchange(question: "Vale no iPad?", answer: "Não")]
        var idea = Idea(title: "Modo offline", body: "Cache local")
        idea.rules = [Rule(text: "Sincroniza ao voltar a rede", details: "ver SyncService")]
        idea.tags = ["ui"]
        let ideaSubject = RuleDiscover.Subject(idea: idea)
        let prompt = RuleDiscover.detailsPrompt(ideaSubject, vocabulary: ["ui", "sync"], topics: [], history: history)
        #expect(prompt.contains("R: Não"))
        #expect(prompt.contains("[must] Sincroniza ao voltar a rede — ver SyncService"))
        #expect(prompt.contains("Critérios de aceite"))
        #expect(prompt.contains("ui, sync"))
        #expect(!prompt.contains("viable"))
        #expect(RuleDiscover.detailsPrompt(subject, vocabulary: [], topics: [], history: []).contains("quando este tópico se aplica"))

        let data = Data(#"{"description":"  ## Problema\nCache  ","reason":"organizei","tags":[{"tag":"UI","reason":"já tem"},{"tag":"Sync","reason":"x"},{"tag":"offline","reason":"y"}]}"#.utf8)
        let answer = try JSONDecoder().decode(RuleDiscover.DetailsAnswer.self, from: data)
        let proposal = RuleDiscover.details(answer, subject: ideaSubject, vocabulary: ["ui", "sync"])
        #expect(proposal.current == "Cache local")
        #expect(proposal.suggested == "## Problema\nCache")
        #expect(proposal.tags.map(\.tag) == ["sync", "offline"])
        #expect(proposal.defaultTags == ["sync"])
        #expect(RuleDiscover.details(.init(description: "Cache local"), subject: ideaSubject, vocabulary: []).isEmpty)

        var body: String? = idea.body
        var tags = idea.tags
        proposal.apply(acceptDescription: false, tags: ["offline"], description: &body, tags: &tags)
        #expect(body == "Cache local" && tags == ["ui", "offline"])
        proposal.apply(acceptDescription: true, tags: [], description: &body, tags: &tags)
        #expect(body == "## Problema\nCache" && tags == ["ui", "offline"])
    }

    @Test func verdictJudgesViabilityWithoutRewriting() throws {
        var idea = Idea(title: "X", body: "b")
        idea.rules = [Rule(text: "R")]
        let prompt = RuleDiscover.verdictPrompt(RuleDiscover.Subject(idea: idea), topics: [])
        #expect(prompt.contains("viable: true só se"))
        #expect(!prompt.contains("description:"))
        let answer = try JSONDecoder().decode(RuleDiscover.VerdictAnswer.self, from: Data(#"{"viable":true,"missing":[" ","x"]}"#.utf8))
        #expect(RuleDiscover.verdict(answer, subject: RuleDiscover.Subject(idea: idea)).missing == ["x"])
        #expect(RuleDiscover.verdict(answer, subject: RuleDiscover.Subject(idea: Idea(title: "Sem regras"))).viable == false)
    }

    @Test func savedViableVerdictApprovesEligibleIdeas() {
        let now = Date(timeIntervalSince1970: 1234)
        for status in [IdeaStatus.new, .exploring, .approved] {
            var idea = Idea(title: "Avaliação")
            idea.status = status
            idea.rules = [Rule(text: "R")]
            let before = idea
            let verdict = RuleDiscoverVerdict(viable: true)
            _ = verdict.readiness(for: idea, now: now)
            #expect(idea == before) // Computing a verdict does not save it.
            verdict.apply(to: &idea, now: now)
            #expect(idea.status == .approved)
            #expect(idea.readiness == verdict.readiness(for: before, now: now))
            #expect(idea.promotedTopic == nil)
            #expect(idea.rules == before.rules)
        }
    }

    @Test func viableVerdictApprovesIdeaWithPendingDependencyWithoutPromoting() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (main, _) = try store.createIdea(title: "Com dependência")
        let (dep, _) = try store.createIdea(title: "Pendente")
        try store.updateIdea(main) { $0.status = .exploring; $0.rules = [Rule(text: "R")] }
        try store.addIdeaDependencies(main, [dep])
        let saved = try store.updateIdea(main) { RuleDiscoverVerdict(viable: true).apply(to: &$0) }.idea
        #expect(saved.status == .approved)
        #expect(saved.promotedTopic == nil)
        #expect(try store.listTopics().isEmpty)
        #expect(throws: VibeDeckError.self) { try store.implementableIdea(main) }
    }

    @Test func savedNonviableVerdictPreservesEveryStatus() {
        for status in IdeaStatus.allCases {
            var idea = Idea(title: "Avaliação")
            idea.status = status
            idea.rules = [Rule(text: "R")]
            idea.readiness = RuleDiscoverVerdict(viable: true).readiness(for: idea)
            RuleDiscoverVerdict(viable: false, missing: ["Qual tela?"]).apply(to: &idea)
            #expect(idea.status == status)
            #expect(idea.readiness?.viable == false)
            #expect(idea.readiness?.missing == ["Qual tela?"])
        }
    }

    @Test func savedVerdictWithoutRulesDoesNotApprove() {
        for status in IdeaStatus.allCases {
            var idea = Idea(title: "Sem regras")
            idea.status = status
            RuleDiscoverVerdict(viable: true).apply(to: &idea)
            #expect(idea.status == status)
            #expect(idea.readiness?.viable == false)
        }
    }

    @Test func savedViableVerdictPreservesClosedAndPromotedIdeas() {
        for status in IdeaStatus.allCases {
            for topic in [nil, "existente"] as [String?] {
                guard status.isClosed || topic != nil else { continue }
                var idea = Idea(title: "Preservada")
                idea.status = status
                idea.promotedTopic = topic
                idea.rules = [Rule(text: "R")]
                RuleDiscoverVerdict(viable: true).apply(to: &idea)
                #expect(idea.status == status)
                #expect(idea.promotedTopic == topic)
                #expect(idea.readiness?.viable == true)
            }
        }
    }

    @Test func savedEvaluationDoesNotCreateOrActivateTopics() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (slug, _) = try store.createIdea(title: "Avaliação")
        try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; $0.paths = ["Sources/**"] }
        let topicsBefore = try store.listTopics().map(\.slug)
        let saved = try store.updateIdea(slug) { RuleDiscoverVerdict(viable: true).apply(to: &$0) }.idea
        #expect(saved.status == .approved)
        #expect(saved.promotedTopic == nil)
        #expect(try store.loadIdea(slug).readiness?.viable == true)
        #expect(try store.listTopics().map(\.slug) == topicsBefore)
    }

    @Test func readinessRoundTripsAndGoesStale() throws {
        var idea = Idea(title: "X", body: "b")
        #expect(!String(decoding: try VDJSON.encode(idea), as: UTF8.self).contains("readiness"))
        #expect(idea.implementBlocker?.contains("Sem regras") == true)

        idea.rules = [Rule(text: "R")]
        #expect(idea.implementBlocker?.contains("não verificada") == true)

        idea.readiness = RuleDiscoverVerdict(viable: true).readiness(for: idea)
        #expect(idea.implementBlocker == nil)
        let decoded = try VDJSON.decoder.decode(Idea.self, from: VDJSON.encode(idea))
        #expect(decoded.readiness?.fingerprint == idea.contentFingerprint)
        #expect(decoded.implementBlocker == nil)

        idea.status = .approved
        idea.promotedTopic = "x"
        idea.tags = ["t"]
        #expect(idea.implementBlocker == nil)

        idea.body = "outra"
        #expect(idea.implementBlocker?.contains("mudou") == true)
        idea.body = "b"
        idea.rules[0].details = "d"
        #expect(idea.implementBlocker?.contains("mudou") == true)

        idea.readiness = RuleDiscoverVerdict(viable: false, missing: ["Qual tela?"]).readiness(for: idea)
        #expect(idea.implementBlocker?.contains("Qual tela?") == true)
        idea.status = .done
        #expect(idea.implementBlocker != nil)
    }

    @Test func implementationPromptWithoutTopicKeepsDraftRulesAndChecks() {
        let prompt = IdeaImplementation.prompt(slug: "rascunho", idea: Idea(title: "Rascunho"), topic: nil)
        #expect(prompt.contains("Siga as regras rascunho da ideia."))
        #expect(!prompt.contains("get_rule_topic"))
        #expect(prompt.contains("rules_for") && prompt.contains("submit_rule_check"))
    }

    @Test func implementationPromptPointsToIdeaTopicAndChecks() {
        let prompt = IdeaImplementation.prompt(slug: "modo-offline", idea: Idea(title: "Modo offline"), topic: "modo-offline")
        #expect(prompt.contains("get_idea (\"modo-offline\")"))
        #expect(prompt.contains("tópico \"modo-offline\""))
        #expect(prompt.contains("rules_for"))
        #expect(prompt.contains("submit_rule_check"))
        #expect(prompt.contains("status=done"))
    }
    @Test func implementationModeRequiresApprovedAndCurrentViableAssessment() {
        var idea = Idea(title: "Elegível")
        idea.rules = [Rule(text: "R")]
        for status in IdeaStatus.allCases {
            idea.status = status
            idea.readiness = nil
            #expect(!IdeaImplementation.isEligible(idea))
            idea.readiness = IdeaReadiness(viable: false, fingerprint: idea.contentFingerprint)
            #expect(!IdeaImplementation.isEligible(idea))
            idea.readiness = IdeaReadiness(viable: true, fingerprint: "antigo")
            #expect(!IdeaImplementation.isEligible(idea))
            idea.readiness = IdeaReadiness(viable: true, fingerprint: idea.contentFingerprint)
            #expect(IdeaImplementation.isEligible(idea) == (status == .approved))
        }
    }

    @Test func implementationIntentContractSeparatesExplicitModesFromQuestions() throws {
        for mode in ["none", "ask", "standard", "workflow"] {
            let data = Data("{\"mode\":\"\(mode)\",\"idea\":null,\"workflow\":null}".utf8)
            #expect(try VDJSON.decoder.decode(IdeaImplementation.ChatIntent.self, from: data).mode.rawValue == mode)
        }
        let idea = Idea(title: "Modo offline")
        let prompt = IdeaImplementation.intentPrompt("Implemente essa ideia sem workflow", context: "Modo offline",
            ideas: [("modo-offline", idea)], workflows: [])
        #expect(prompt.contains(idea.id.uuidString))
        #expect(prompt.contains("standard"))
        #expect(prompt.contains("Não execute comandos nem altere arquivos"))
        #expect(prompt.contains("referência ambígua"))
    }

}
