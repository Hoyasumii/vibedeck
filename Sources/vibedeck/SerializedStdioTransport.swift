import Foundation
import Logging
import MCP

/// Preserve whole JSON-RPC messages when a large tools/list reply fills stdout's nonblocking pipe.
/// StdioTransport suspends on backpressure, allowing another send to interleave without this gate.
actor SerializedStdioTransport: Transport {
    let logger = Logger(label: "vibedeck.mcp.transport", factory: { _ in SwiftLogNoOpLogHandler() })
    private let base = StdioTransport()
    private let messages = AsyncThrowingStream<Data, Error>.makeStream()
    private var reader: Task<Void, Never>?
    private var sending = false
    private var pending: [CheckedContinuation<Void, Never>] = []

    func connect() async throws {
        try await base.connect()
        reader = Task {
            do {
                for try await message in await base.receive() { messages.continuation.yield(message) }
                messages.continuation.finish()
            } catch { messages.continuation.finish(throwing: error) }
        }
    }
    func disconnect() async {
        reader?.cancel(); reader = nil
        await base.disconnect()
        messages.continuation.finish()
    }
    func receive() -> AsyncThrowingStream<Data, Error> { messages.stream }
    func send(_ data: Data) async throws {
        if sending { await withCheckedContinuation { pending.append($0) } }
        else { sending = true }
        defer {
            if pending.isEmpty { sending = false }
            else { pending.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await base.send(data)
    }
}
