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

    /// The returned stream's cancellation (e.g. the consuming `for await` loop's `Task` being
    /// cancelled) cascades to every in-flight per-source search via structured concurrency --
    /// there's no separate "stop" plumbing needed beyond standard `Task` cancellation.
    public static func search(sources: [BookSource], keyword: String, httpClient: HTTPClient) -> AsyncStream<SourceOutcome> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SourceOutcome.self) { group in
                    for source in sources {
                        group.addTask {
                            do {
                                let results = try await SearchService.search(source: source, keyword: keyword, httpClient: httpClient)
                                return SourceOutcome(source: source, results: results)
                            } catch {
                                return SourceOutcome(source: source, results: [], errorDescription: "\(error)")
                            }
                        }
                    }
                    for await outcome in group {
                        continuation.yield(outcome)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
