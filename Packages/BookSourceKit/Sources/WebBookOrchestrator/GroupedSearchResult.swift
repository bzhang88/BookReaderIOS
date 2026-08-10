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
    public var wordCount: String? { entries.lazy.compactMap(\.wordCount).first }
    public var sourceCount: Int { entries.count }

    static func groupKey(for result: SearchResult) -> String {
        groupKey(name: result.name, author: result.author)
    }

    /// Same (name, author) normalization as the merge key above, exposed so callers outside this
    /// module (e.g. checking whether a search result is already on the shelf) can compute a
    /// matching key from any name/author pair -- a `ShelfBook` included -- without needing to
    /// construct a throwaway `SearchResult` just to reuse the trimming rule.
    public static func groupKey(name: String, author: String?) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedName)|\(trimmedAuthor)"
    }
}

extension Array where Element == GroupedSearchResult {
    /// Ranks settled search results the way a merged multi-source list should read: books
    /// confirmed by more sources first (more likely a real, correctly-matched title rather than a
    /// stray one-off hit), source count descending, otherwise preserving arrival order -- Swift's
    /// `sorted(by:)` is a stable sort, so ties keep whichever order they streamed in.
    public func rankedBySourceCount() -> [GroupedSearchResult] {
        sorted { $0.sourceCount > $1.sourceCount }
    }

    /// Ranks by how closely each title matches `query`, not by how many sources carry it -- a book
    /// that only exists on one source (and so always loses a by-source-count sort, however well it
    /// matches) still needs a way to surface near the top. Tiers: exact title match, then prefix
    /// match, then substring match, then everything else; source count only breaks ties within a
    /// tier, so a well-matched single-source book still outranks a poorly-matched multi-source one.
    public func rankedByRelevance(query: String) -> [GroupedSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func tier(_ group: GroupedSearchResult) -> Int {
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == normalizedQuery { return 0 }
            if name.hasPrefix(normalizedQuery) { return 1 }
            if name.contains(normalizedQuery) { return 2 }
            return 3
        }
        return sorted { lhs, rhs in
            let lhsTier = tier(lhs)
            let rhsTier = tier(rhs)
            if lhsTier != rhsTier { return lhsTier < rhsTier }
            return lhs.sourceCount > rhs.sourceCount
        }
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
