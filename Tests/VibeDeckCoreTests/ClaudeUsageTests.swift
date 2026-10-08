import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ClaudeUsageTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let statusLine = Data("""
    {"session_id":"abc","model":{"id":"claude-opus-5-5","display_name":"Opus"},
     "rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":1791460800},
                    "seven_day":{"used_percentage":18,"resets_at":1791936000}}}
    """.utf8)

    @Test func parsesStatusLineAndRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_791_450_000)
        let usage = try ClaudeUsage.fromStatusLine(statusLine, now: now)
        #expect(usage.model == "Opus")
        #expect(usage.session?.usedPercentage == 42.4)
        #expect(usage.session?.resetsAt == Date(timeIntervalSince1970: 1_791_460_800))
        #expect(usage.weekly?.usedPercentage == 18)
        #expect(usage.summary(at: now).contains("sessão 42%"))

        let url = tempDir().appending(path: "usage.json")
        try ClaudeCode.recordUsage(statusLine: statusLine, to: url, now: now)
        #expect(ClaudeCode.loadUsage(from: url) == usage)

        // Sem rate_limits (ex.: chave de API) o último valor conhecido fica.
        let empty = try ClaudeCode.recordUsage(statusLine: Data(#"{"model":{"display_name":"Opus"}}"#.utf8), to: url)
        #expect(!empty.hasLimits)
        #expect(ClaudeCode.loadUsage(from: url) == usage)
    }

    @Test func windowResetsToZeroAfterResetTime() {
        let reset = Date(timeIntervalSince1970: 1000)
        let window = ClaudeUsage.Window(usedPercentage: 80, resetsAt: reset)
        #expect(window.percentage(at: Date(timeIntervalSince1970: 999)) == 80)
        #expect(window.percentage(at: Date(timeIntervalSince1970: 1000)) == 0)
    }

    @Test func installChainsExistingStatusLineAndUninstallRestoresIt() throws {
        let settings = tempDir().appending(path: "settings.json")
        try Data(#"{"model":"opus","statusLine":{"type":"command","command":"echo 'oi'","padding":0}}"#.utf8).write(to: settings)

        try ClaudeCode.installStatusLine(executable: "/Users/me/.local/bin/vibedeck", settings: settings)
        #expect(try ClaudeCode.statusLineState(settings: settings) == .vibedeck(previous: "echo 'oi'"))
        let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        #expect(installed?["model"] as? String == "opus")
        #expect((installed?["statusLine"] as? [String: Any])?["padding"] as? Int == 0)

        // Reinstalar não encadeia de novo.
        try ClaudeCode.installStatusLine(executable: "/Users/me/.local/bin/vibedeck", settings: settings)
        #expect(try ClaudeCode.statusLineState(settings: settings) == .vibedeck(previous: "echo 'oi'"))

        try ClaudeCode.uninstallStatusLine(settings: settings)
        #expect(try ClaudeCode.statusLineState(settings: settings) == .other("echo 'oi'"))
    }

    @Test func installWithoutSettingsFileAndUninstallRemovesIt() throws {
        let settings = tempDir().appending(path: "settings.json")
        #expect(try ClaudeCode.statusLineState(settings: settings) == .none)
        try ClaudeCode.installStatusLine(executable: "vibedeck", settings: settings)
        #expect(try ClaudeCode.statusLineState(settings: settings) == .vibedeck(previous: nil))
        try ClaudeCode.uninstallStatusLine(settings: settings)
        #expect(try ClaudeCode.statusLineState(settings: settings) == .none)
    }
}
