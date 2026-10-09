import Foundation

/// A file the agent changed whose applicable rules have no approved check since the change.
public struct UnverifiedChange: Encodable, Equatable, Sendable {
    public var file: String
    public var topics: [String]
    /// The newest check covering the file's topics after the change failed (instead of not existing).
    public var lastCheckFailed: Bool
}

/// Gate of the Claude Code `Stop` hook: the agent can't end its turn while a file it changed has
/// applicable rules without an approved check recorded after the change.
extension ProjectStore {
    /// Files that change as a side effect (check records, run state, the guide regenerated from AgentsGuide.swift,
    /// granted permissions) and never need a check of their own.
    static let stopGateIgnored = [".vibedeck/checks/", ".vibedeck/runs/", ".vibedeck/AGENTS.md", ".claude/settings.local.json"]

    /// Files changed in the working tree (tracked against HEAD, plus untracked), with their modification
    /// date, keeping only those modified at or after `since`. Deleted files have no date and are skipped.
    public func workingTreeChanges(since: Date) -> [(file: String, modified: Date)] {
        let tracked = Git.run(["diff", "--name-only", "--relative", "-z", "HEAD"], in: root)
        let untracked = Git.run(["ls-files", "--others", "--exclude-standard", "-z"], in: root)
        let paths = Set([tracked, untracked].filter(\.ok).flatMap { $0.stdout.split(separator: "\0").map(String.init) })
        return paths.sorted().compactMap { path in
            guard !Self.stopGateIgnored.contains(where: { path.hasPrefix($0) }),
                  let modified = (try? FileManager.default.attributesOfItem(atPath: root.appending(path: path).path))?[.modificationDate] as? Date,
                  modified >= since
            else { return nil }
            return (path, modified)
        }
    }

    /// Changed files that still need an approved check: the newest check recorded after the change that
    /// covers all of the file's applicable topics must have passed. Files without applicable rules are free.
    public func unverifiedChanges(_ changes: [(file: String, modified: Date)]) throws -> [UnverifiedChange] {
        let checks = try listChecks()
        return try changes.compactMap { change in
            let topics = try applicableTopics(files: [change.file]).filter { !$0.topic.rules.isEmpty }.map(\.slug)
            guard !topics.isEmpty else { return nil }
            // Check dates are stored without fractional seconds: allow the second they were truncated from.
            let covering = checks.first {
                $0.createdAt.addingTimeInterval(1) >= change.modified && Set($0.topics).isSuperset(of: topics)
            }
            if covering?.passed == true { return nil }
            return UnverifiedChange(file: relativePath(change.file), topics: topics, lastCheckFailed: covering != nil)
        }
    }

    /// The reason handed back to the agent when the gate blocks.
    public static func stopGateReason(_ unverified: [UnverifiedChange]) -> String {
        let listed = unverified.prefix(15).map { change in
            "- \(change.file) (\(change.topics.joined(separator: ", ")))\(change.lastCheckFailed ? " — o último check falhou" : "")"
        }
        let more = unverified.count > 15 ? ["- … e mais \(unverified.count - 15)"] : []
        return """
        VibeDeck: a tarefa não pode ser concluída sem um check de regras aprovado depois das alterações. \
        Arquivos alterados sem check:
        \((listed + more).joined(separator: "\n"))
        Chame `rules_for` (ou `vibedeck rules for <arquivos> --json`) com esses arquivos, verifique cada regra \
        e envie `submit_rule_check` (ou `vibedeck rules check`). Se falhar, corrija e envie de novo.
        """
    }
}

// MARK: - Instalação do hook

/// The coding agents whose hooks speak the same `Stop` protocol (JSON on stdin, `{"decision":"block"}` on stdout).
public enum HookAgent: String, CaseIterable, Sendable {
    case claude, codex

    /// Codex may send `transcript_path: null`, so it also gets a `SessionStart` hook that marks when the session began.
    public var needsSessionStart: Bool { self == .codex }
}

extension ClaudeCode {
    static let stopHookMarker = "hook stop"
    static let sessionStartMarker = "hook start"

    /// Whether the settings/hooks file has the VibeDeck `Stop` hook.
    public static func hasStopHook(settings url: URL) throws -> Bool {
        hookEntries(try readSettings(url), event: "Stop").contains { isVibeDeckHook($0, marker: stopHookMarker) }
    }

    /// Adds the VibeDeck `Stop` hook (`<executable> hook stop`), plus `SessionStart` (`<executable> hook start`)
    /// when `sessionStart`, to a Claude Code settings file or a Codex `hooks.json` (same layout), replacing
    /// previous VibeDeck entries and keeping every other hook.
    public static func installStopHook(executable: String, settings url: URL, sessionStart: Bool = false) throws {
        var settings = try readSettings(url)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var events = [("Stop", stopHookMarker)]
        if sessionStart { events.append(("SessionStart", sessionStartMarker)) }
        for (event, marker) in events {
            var entries = hookEntries(settings, event: event).filter { !isVibeDeckHook($0, marker: marker) }
            entries.append(["hooks": [["type": "command", "command": "\(shellQuote(executable)) \(marker)", "timeout": 600]]])
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        try writeSettings(settings, to: url)
    }

    /// Removes the VibeDeck `Stop` and `SessionStart` hooks, dropping keys that end up empty.
    public static func uninstallStopHook(settings url: URL) throws {
        var settings = try readSettings(url)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, marker) in [("Stop", stopHookMarker), ("SessionStart", sessionStartMarker)] where hooks[event] != nil {
            let entries = hookEntries(settings, event: event).filter { !isVibeDeckHook($0, marker: marker) }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(settings, to: url)
    }

    private static func hookEntries(_ settings: [String: Any], event: String) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    private static func isVibeDeckHook(_ entry: [String: Any], marker: String) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String).map { $0.contains("vibedeck") && $0.hasSuffix(marker) } ?? false
        }
    }
}
