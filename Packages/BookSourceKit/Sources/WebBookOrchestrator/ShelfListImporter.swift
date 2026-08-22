import Foundation
import BookSourceModel
import NetworkClient

/// Resolves a portable `ShelfListEntry` list (imported from a URL, pasted JSON, or a local file --
/// the app target decides which) against the user's own configured sources -- the search/matching
/// half of Legado_Max's own `importBookshelf`. Writing resolved matches onto the shelf itself stays
/// in the app target (`ShelfStore`/`BookInfoService` orchestration, same shape as `ShelfView
/// .switchSource`), since this package has no shelf-store dependency to write through.
public enum ShelfListImporter {
    public struct Match: Sendable {
        public let entry: ShelfListEntry
        public let source: BookSource
        public let result: SearchResult
    }

    /// Searches every entry's name across `sources` (draining each entry's full result stream, the
    /// same pattern the app target's own `ShelfView.findExactMatchSource` already uses for batch
    /// 换源), keeping only an exact name+author match. An entry with no `author` at all (a common
    /// real-world 书单 shape, per Legado's own export only ever writing `name`/`author`/`intro`)
    /// still requires the matched result's author to also be blank -- matching on name alone against
    /// *any* author would too easily grab the wrong book under a shared title.
    public static func resolve(
        entries: [ShelfListEntry], sources: [BookSource], httpClient: HTTPClient
    ) async -> (matches: [Match], unmatched: [ShelfListEntry]) {
        var matches: [Match] = []
        var unmatched: [ShelfListEntry] = []
        for entry in entries {
            let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            var allResults: [SearchResult] = []
            let stream = MultiSourceSearchService.search(sources: sources, keyword: trimmedName, httpClient: httpClient)
            for await outcome in stream {
                allResults.append(contentsOf: outcome.results)
            }
            if let result = allResults.first(where: { $0.name == trimmedName && matchesAuthor($0.author, entry.author) }),
               let source = sources.first(where: { $0.bookSourceUrl == result.bookSourceUrl }) {
                matches.append(Match(entry: entry, source: source, result: result))
            } else {
                unmatched.append(entry)
            }
        }
        return (matches, unmatched)
    }

    private static func matchesAuthor(_ resultAuthor: String?, _ entryAuthor: String?) -> Bool {
        let normalizedResult = (resultAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEntry = (entryAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedResult == normalizedEntry
    }
}
