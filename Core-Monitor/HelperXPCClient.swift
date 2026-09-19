import Foundation

/// Reuses one connection so the helper can associate fan ownership with this
/// app session. Replies, timeouts, and disconnects complete on the main actor.
@MainActor
final class HelperXPCClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let makeConnection: () -> NSXPCConnection
    private var connection: NSXPCConnection?
    private var connectionID: UUID?
    private var pending: [UUID: (String) -> Void] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]

    var isConnected: Bool { connection != nil }

    init(makeConnection: @escaping () -> NSXPCConnection) {
        self.makeConnection = makeConnection
    }

    func disconnect(reason: String = "Helper connection ended.") {
        let old = connection
        connection = nil
        connectionID = nil
        let completions = Array(pending.values)
        pending.removeAll()
        for timeout in timeouts.values { timeout.cancel() }
        timeouts.removeAll()
        old?.invalidate()
        for finish in completions { finish(reason) }
    }

    private func connected() -> NSXPCConnection {
        if let connection { return connection }
        let next = makeConnection()
        let id = UUID()
        next.remoteObjectInterface = NSXPCInterface(with: SMCHelperXPCProtocol.self)
        let interrupted: () -> Void = { [weak self] in
            Task { @MainActor in
                guard self?.connectionID == id else { return }
                self?.disconnect(reason: "Helper connection was interrupted.")
            }
        }
        next.invalidationHandler = interrupted
        next.interruptionHandler = interrupted
        connection = next
        connectionID = id
        next.resume()
        return next
    }

    func request<Value: Sendable>(
        timeout: TimeInterval,
        perform: (SMCHelperXPCProtocol, @escaping (Value?, String?) -> Void) -> Void
    ) async throws -> Value {
        try Task.checkCancellation()
        let connection = connected()
        let sessionID = connectionID
        let requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            let finish: @MainActor (Value?, String?) -> Void = { [weak self] value, error in
                guard !completed else { return }
                completed = true
                self?.pending.removeValue(forKey: requestID)
                self?.timeouts.removeValue(forKey: requestID)?.cancel()
                if let error { continuation.resume(throwing: Failure(message: error)) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: Failure(message: "Helper returned no result.")) }
            }
            pending[requestID] = { finish(nil, $0) }
            timeouts[requestID] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(max(0.001, timeout) * 1_000_000_000)) }
                catch { return }
                guard self?.connectionID == sessionID, self?.pending[requestID] != nil else { return }
                // Invalidating the session also makes the helper release its
                // fans, including a write whose reply did not arrive in time.
                self?.disconnect(reason: "Timed out while waiting for privileged helper.")
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in
                    guard self?.connectionID == sessionID else { return }
                    self?.disconnect(reason: message)
                }
            }) as? SMCHelperXPCProtocol else {
                disconnect(reason: "Failed to create helper connection.")
                return
            }
            perform(proxy) { value, error in
                Task { @MainActor in finish(value, error) }
            }
        }
    }
}
