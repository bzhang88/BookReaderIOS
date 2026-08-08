import Foundation

public struct RequestTimeoutError: Error, Equatable {}

/// Races `operation` against a timer, throwing `RequestTimeoutError` if it doesn't finish first.
///
/// A defensive backstop, not the primary timeout mechanism: `URLRequest.timeoutInterval` is set
/// on every real request too, but was observed (on this platform's `FoundationNetworking` port)
/// to not always fire for certain connection-establishment hangs against dead/slow real-world
/// sites. A book source that never responds shouldn't be able to hang the app indefinitely.
public func withRequestTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            throw RequestTimeoutError()
        }
        guard let result = try await group.next() else { throw RequestTimeoutError() }
        group.cancelAll()
        return result
    }
}
