import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct CloudSessionTests {
    private func sync(_ counts: String, porcelain: String = "", remote: String? = "git@github.com:Hoyasumii/vibedeck.git") -> CloudSync {
        CloudSync.evaluate(revListCounts: counts, porcelain: porcelain, remoteURL: remote, branch: "main")
    }

    @Test func inSyncDoesNotBlock() {
        let result = sync("0\t0\n")
        #expect(result.problem == nil)
        #expect(!result.blocked)
        #expect(result.dirty.isEmpty)
    }

    @Test func remoteBehindBlocks() {
        let result = sync("2\t0\n")
        #expect(result.problem == .remoteBehind(2))
        #expect(result.message.contains("origin/main está 2 commits atrás"))
        #expect(result.message.contains("precisam ser iguais"))
    }

    @Test func localBehindBlocks() {
        #expect(sync("0\t1").problem == .localBehind(1))
    }

    @Test func divergedBlocks() {
        #expect(sync("3\t4").problem == .diverged(ahead: 3, behind: 4))
    }

    @Test func requiresGitHubOrigin() {
        #expect(sync("0\t0", remote: nil).problem == .noOrigin)
        #expect(sync("0\t0", remote: "").problem == .noOrigin)
        #expect(sync("0\t0", remote: "git@gitlab.com:a/b.git").problem == .notGitHub("git@gitlab.com:a/b.git"))
        #expect(sync("0\t0", remote: "https://github.com/a/b").problem == nil)
    }

    @Test func dirtyTreeWarnsWithoutBlocking() {
        let result = sync("0\t0", porcelain: " M Sources/App.swift\n?? notes.md\n")
        #expect(!result.blocked)
        #expect(result.dirty == ["Sources/App.swift", "notes.md"])
        #expect(result.message.contains("2 arquivo(s) não commitado(s)"))
    }

    @Test func parsesSessionURL() {
        let output = "\u{1B}[32m✓\u{1B}[0m Cloud session created: https://claude.ai/code/session_01AbC-x_9.\nAttaching…"
        #expect(CloudSession.parseSessionURL(output)?.absoluteString == "https://claude.ai/code/session_01AbC-x_9")
        #expect(CloudSession.parseSessionURL("no link here") == nil)
        #expect(CloudSession.parseSessionURL("see https://example.com/code/x") == nil)
    }

    @Test func checksRealRepo() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vd-cloud-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(CloudSession.check(root: dir).problem == .notARepo)
        _ = Git.run(["init", "-q"], in: dir)
        #expect(CloudSession.check(root: dir).problem == .noOrigin)
    }
}
