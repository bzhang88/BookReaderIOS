import Foundation
import BookSourceModel
import NetworkClient

/// Searches multiple sources concurrently, streaming each source's outcome back as it completes
/// rather than waiting for every source to finish before returning anything -- real book-source
/// searching is normally done across a whole library at once (not one source picked ahead of
/// time), and individual sources are frequently slow or dead, so results need to show up
/// incrementally and the whole thing needs to be cancelable mid-flight.
public enum MultiSourceSearchService {
    public struct SourceOutcome: Equatable {
        public var source: BookSource
        public var results: [SearchResult]
        public var errorDescription: String?

        public init(source: BookSource, results: [SearchResult], errorDescription: String? = nil) {
            self.source = source
            self.results = results
            self.errorDescription = errorDescription
        }
    }

    /// Real gap found comparing against Legado: this used to fire every source's search
    /// simultaneously with no cap at all, via `for source in sources { group.addTask { ... } } --
    /// harmless for a handful of sources, but a real Legado-sized collection (50-200+ enabled
    /// sources is normal) meant a single global search opened that many concurrent HTTP connections
    /// at once. Legado's own `AppConfig.threadCount` (user-configurable, defaults to 16) caps this;
    /// `maxConcurrent` mirrors that default here.
    public static let defaultMaxConcurrent = 16

    /// The returned stream's cancellation (e.g. the consuming `for await` loop's `Task` being
    /// cancelled) cascades to every in-flight per-source search via structured concurrency --
    /// there's no separate "stop" plumbing needed beyond standard `Task` cancellation. At most
    /// `maxConcurrent` sources search simultaneously: the group is seeded with that many tasks, and
    /// each time one finishes, the next not-yet-started source (if any) is added -- a standard
    /// bounded worker-pool shape for `TaskGroup`, not a batch-then-wait-then-next-batch one, so
    /// results still stream out continuously rather than in stalled chunks.
    public static func search(
        sources: [BookSource], keyword: String, httpClient: HTTPClient, maxConcurrent: Int = defaultMaxConcurrent
    ) -> AsyncStream<SourceOutcome> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SourceOutcome.self) { group in
                    var remaining = sources[...]
                    func addNext() {
                        guard let source = remaining.first else { return }
                        remaining = remaining.dropFirst()
                        group.addTask {
                            do {
                                let results = try await SearchService.search(source: source, keyword: keyword, httpClient: httpClient)
                                return SourceOutcome(source: source, results: results)
                            } catch {
                                return SourceOutcome(source: source, results: [], errorDescription: FriendlyError.message(for: error))
                            }
                        }
                    }
                    for _ in 0..<max(1, min(maxConcurrent, sources.count)) {
                        addNext()
                    }
                    for await outcome in group {
                        continuation.yield(outcome)
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
