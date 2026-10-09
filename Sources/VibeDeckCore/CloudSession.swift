import Foundation
import Synchronization

/// Minimal git runner for the cloud check: `/usr/bin/git` in the project root, with the login shell's PATH.
enum Git {
    struct Output {
        var stdout: String
        var stderr: String
        var status: Int32
        var ok: Bool { status == 0 }
    }

    static func run(_ arguments: [String], in root: URL) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ClaudeCode.childPATH()
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Output(stdout: "", stderr: error.localizedDescription, status: -1) }
        // Read stderr concurrently so a chatty command can't fill its pipe and deadlock.
        nonisolated(unsafe) var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return Output(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            status: process.terminationStatus
        )
    }
}

/// Whether the local default branch matches GitHub, which is all a Claude Code cloud session can see.
public struct CloudSync: Equatable, Sendable, Encodable {
    public enum Problem: Equatable, Sendable {
        case notARepo
        case noOrigin
        case notGitHub(String)
        case fetchFailed(String)
        /// origin/<branch> lacks this many local commits.
        case remoteBehind(Int)
        /// The local branch lacks this many commits from origin/<branch>.
        case localBehind(Int)
        case diverged(ahead: Int, behind: Int)
    }

    public var branch: String
    public var remoteURL: String?
    /// Local commits missing from origin/<branch>.
    public var ahead: Int
    /// origin/<branch> commits missing locally.
    public var behind: Int
    /// Uncommitted paths (`git status --porcelain`); they don't block, but the cloud won't see them.
    public var dirty: [String]
    public var problem: Problem?

    public var blocked: Bool { problem != nil }

    public var message: String {
        let remote = "origin/\(branch)"
        switch problem {
        case .notARepo: return "Este projeto não é um repositório git."
        case .noOrigin: return "O repositório não tem o remoto `origin`. A sessão na nuvem roda sobre o GitHub."
        case .notGitHub(let url): return "O remoto `origin` (\(url)) não está no GitHub. A sessão na nuvem só funciona com repositórios do GitHub."
        case .fetchFailed(let error): return "Não foi possível consultar o GitHub (git fetch): \(error)"
        case .remoteBehind(let n):
            return "A \(remote) está \(commits(n)) atrás da sua \(branch) local. Dê push: as branches precisam ser iguais para usar a nuvem."
        case .localBehind(let n):
            return "A sua \(branch) local está \(commits(n)) atrás da \(remote). Dê pull: as branches precisam ser iguais para usar a nuvem."
        case .diverged(let ahead, let behind):
            return "A \(branch) local e a \(remote) divergiram (\(commits(ahead)) só aqui, \(commits(behind)) só no GitHub). Sincronize: as branches precisam ser iguais para usar a nuvem."
        case nil:
            return dirty.isEmpty
                ? "A \(branch) local e a \(remote) são iguais."
                : "A \(branch) local e a \(remote) são iguais, mas há \(dirty.count) arquivo(s) não commitado(s) que a nuvem não vai ver."
        }
    }

    private func commits(_ n: Int) -> String { n == 1 ? "1 commit" : "\(n) commits" }

    /// Builds the result from git's raw output: `rev-list --left-right --count <branch>...origin/<branch>`
    /// prints "<ahead>\t<behind>".
    public static func evaluate(revListCounts: String, porcelain: String, remoteURL: String?, branch: String) -> CloudSync {
        let dirty = porcelain.split(separator: "\n").map { String($0.dropFirst(3)) }.filter { !$0.isEmpty }
        let counts = revListCounts.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        let ahead = counts.first ?? 0, behind = counts.count > 1 ? counts[1] : 0
        var sync = CloudSync(branch: branch, remoteURL: remoteURL, ahead: ahead, behind: behind, dirty: dirty)
        guard let remoteURL, !remoteURL.isEmpty else { sync.problem = .noOrigin; return sync }
        guard remoteURL.contains("github.com") else { sync.problem = .notGitHub(remoteURL); return sync }
        switch (ahead, behind) {
        case (0, 0): break
        case (_, 0): sync.problem = .remoteBehind(ahead)
        case (0, _): sync.problem = .localBehind(behind)
        default: sync.problem = .diverged(ahead: ahead, behind: behind)
        }
        return sync
    }

    init(branch: String, remoteURL: String?, ahead: Int = 0, behind: Int = 0, dirty: [String] = [], problem: Problem? = nil) {
        self.branch = branch
        self.remoteURL = remoteURL
        self.ahead = ahead
        self.behind = behind
        self.dirty = dirty
        self.problem = problem
    }

    enum CodingKeys: String, CodingKey { case branch, remoteURL, ahead, behind, dirty, blocked, message }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(branch, forKey: .branch)
        try c.encodeIfPresent(remoteURL, forKey: .remoteURL)
        try c.encode(ahead, forKey: .ahead)
        try c.encode(behind, forKey: .behind)
        try c.encode(dirty, forKey: .dirty)
        try c.encode(blocked, forKey: .blocked)
        try c.encode(message, forKey: .message)
    }
}

/// Claude Code cloud sessions (claude.ai/code), created with `claude --cloud` on the project's GitHub repo.
/// Both calls block, so callers off the main thread only.
public enum CloudSession {
    /// Fetches the default branch from origin and compares it with the local one.
    public static func check(root: URL) -> CloudSync {
        guard Git.run(["rev-parse", "--is-inside-work-tree"], in: root).ok else {
            return CloudSync(branch: "main", remoteURL: nil, problem: .notARepo)
        }
        let remote = Git.run(["remote", "get-url", "origin"], in: root)
        let remoteURL = remote.ok ? remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let head = Git.run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root)
        let branch = head.ok ? String(head.stdout.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst("origin/".count)) : "main"
        let porcelain = Git.run(["status", "--porcelain"], in: root).stdout
        var sync = CloudSync.evaluate(revListCounts: "", porcelain: porcelain, remoteURL: remoteURL, branch: branch)
        guard sync.problem == nil else { return sync }

        let fetch = Git.run(["fetch", "origin", branch, "--quiet"], in: root)
        guard fetch.ok else { sync.problem = .fetchFailed(fetch.stderr); return sync }
        let counts = Git.run(["rev-list", "--left-right", "--count", "\(branch)...origin/\(branch)"], in: root)
        guard counts.ok else { sync.problem = .fetchFailed(counts.stderr); return sync }
        return CloudSync.evaluate(revListCounts: counts.stdout, porcelain: porcelain, remoteURL: remoteURL, branch: branch)
    }

    /// Checks the branch, then runs `claude --cloud <description>` and returns the session's URL.
    /// Refuses when the branches differ, and when the tree is dirty unless `allowDirty`.
    public static func launch(root: URL, description: String, allowDirty: Bool, timeout: TimeInterval = 120, provider: AIProvider = .claude, environment: String? = nil) throws -> (sync: CloudSync, url: URL?, output: String) {
        let sync = check(root: root)
        if sync.blocked { throw VibeDeckError.cloudNotSynced(sync) }
        if !sync.dirty.isEmpty, !allowDirty { throw VibeDeckError.cloudDirty(sync) }
        guard let executable = provider.executable else { throw VibeDeckError.cloudSessionFailed("\(provider.title) não está instalado.") }
        let cloudEnvironment = environment ?? (try? ProjectStore(root: root).loadProject().codexCloudEnvironment)
        if provider == .codex, cloudEnvironment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw VibeDeckError.cloudSessionFailed("Configure o ambiente do Codex Cloud (--env) antes de criar a sessão.")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = provider == .claude ? ["--cloud", description] : ["cloud", "exec", "--env", cloudEnvironment!, "--branch", sync.branch, description]
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ClaudeCode.childPATH()
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        // `--cloud` may stay attached to the session it creates, so the output is read as it arrives and
        // the process is stopped once the session's link shows up (or after `timeout`).
        let collected = Mutex(Data())
        let found = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            let text = collected.withLock { data -> String in
                data.append(chunk)
                return String(decoding: data, as: UTF8.self)
            }
            if chunk.isEmpty || parseSessionURL(text, provider: provider) != nil {
                handle.readabilityHandler = nil
                found.signal()
            }
        }
        do { try process.run() } catch { throw VibeDeckError.cloudSessionFailed(error.localizedDescription) }
        _ = found.wait(timeout: .now() + timeout)
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let output = collected.withLock { String(decoding: $0, as: UTF8.self) }.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = parseSessionURL(output, provider: provider)
        if url == nil, process.terminationStatus != 0 || output.isEmpty { throw VibeDeckError.cloudSessionFailed(output) }
        return (sync, url, output)
    }

    /// First claude.ai/code link in `claude --cloud`'s output (which may carry ANSI colors).
    public static func parseSessionURL(_ output: String, provider: AIProvider = .claude) -> URL? {
        if provider == .codex {
            guard let match = output.firstMatch(of: /https:\/\/(?:chatgpt\.com|chat\.openai\.com)\/codex\/[A-Za-z0-9_\-\/?=&.%]+/) else { return nil }
            return URL(string: String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".?&")))
        }
        guard let match = output.firstMatch(of: /https:\/\/claude\.ai\/code\/[A-Za-z0-9_\-\/?=&.%]+/) else { return nil }
        var link = String(match.output)
        while let last = link.last, ".?&".contains(last) { link.removeLast() }
        return URL(string: link)
    }
}
