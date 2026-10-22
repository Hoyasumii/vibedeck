import Foundation

/// A file the agent changed whose applicable rules have no approved check since the change.
struct UnverifiedChange: Encodable, Equatable, Sendable {
    var file: String
    var topics: [String]
    /// The newest check covering the file's topics after the change failed (instead of not existing).
    var lastCheckFailed: Bool
}


// MARK: - Instalação do hook

/// The coding agents whose hooks speak the same `Stop` protocol (JSON on stdin, `{"decision":"block"}` on stdout).
enum HookAgent: String, CaseIterable, Sendable {
    case claude, codex

    /// Codex may send `transcript_path: null`, so it also gets a `SessionStart` hook that marks when the session began.
    var needsSessionStart: Bool { self == .codex }
}

extension ClaudeCode {
    static let stopHookMarker = "hook stop"
    static let sessionStartMarker = "hook start"

    /// Whether the settings/hooks file has the VibeDeck `Stop` hook.
    static func hasStopHook(settings url: URL) throws -> Bool {
        hookEntries(try readSettings(url), event: "Stop").contains { isVibeDeckHook($0, marker: stopHookMarker) }
    }

    /// Adds the VibeDeck `Stop` hook (`<executable> hook stop`), plus `SessionStart` (`<executable> hook start`)
    /// when `sessionStart`, to a Claude Code settings file or a Codex `hooks.json` (same layout), replacing
    /// previous VibeDeck entries and keeping every other hook.
    static func installStopHook(executable: String, settings url: URL, sessionStart: Bool = false) throws {
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
    static func uninstallStopHook(settings url: URL) throws {
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
