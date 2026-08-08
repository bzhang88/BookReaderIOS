import Foundation

/// A book found by one or more sources, grouped by (name, author) -- mirrors Legado's search
/// results screen, where the same novel found on several sites shows up as a single entry ("共 N
/// 个源") instead of N duplicate rows, so the user can pick whichever source currently works
/// rather than hunting through repeats of the same title.
public struct GroupedSearchResult: Identifiable, Equatable {
    /// Every source's hit for this book, in the order they arrived.
    public var entries: [SearchResult]

    public init(entries: [SearchResult]) {
        self.entries = entries
    }

    public var id: String { Self.groupKey(for: entries[0]) }

    public var name: String { entries[0].name }
    public var author: String? { entries[0].author }
    /// The most detailed intro found across every source that has this book, not just the first.
    public var intro: String? { entries.compactMap(\.intro).max(by: { $0.count < $1.count }) }
    public var lastChapter: String? { entries.lazy.compactMap(\.lastChapter).first }
    public var coverUrl: String? { entries.lazy.compactMap(\.coverUrl).first }
    public var sourceCount: Int { entries.count }

    static func groupKey(for result: SearchResult) -> String {
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (result.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name)|\(author)"
    }
}

/// Groups (and incrementally re-groups, as more sources' results stream in) `SearchResult`s by
/// book -- exact (name, author) match, same as Legado's merge key. Deliberately not fuzzy: fuzzy
/// title matching across independently-run sites is unreliable and would risk merging two
/// genuinely different books that just happen to share a title.
public enum SearchResultGrouper {
    /// Folds `newResults` into `existing`, preserving `existing`'s group order and each existing
    /// group's own entry order -- new hits for an already-seen book are appended to that group;
    /// genuinely new books become new groups appended at the end. Safe to call once per source as
    /// results stream in from `MultiSourceSearchService`.
    public static func merge(_ newResults: [SearchResult], into existing: [GroupedSearchResult]) -> [GroupedSearchResult] {
        var groups = existing
        var indexByKey: [String: Int] = [:]
        for (i, group) in groups.enumerated() {
            indexByKey[GroupedSearchResult.groupKey(for: group.entries[0])] = i
        }

        for result in newResults {
            let key = GroupedSearchResult.groupKey(for: result)
            if let idx = indexByKey[key] {
                groups[idx].entries.append(result)
            } else {
                indexByKey[key] = groups.count
                groups.append(GroupedSearchResult(entries: [result]))
            }
        }
        return groups
    }
}
