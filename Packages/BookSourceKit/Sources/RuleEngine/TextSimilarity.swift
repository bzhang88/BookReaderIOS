import Foundation

/// Normalized string similarity for bucketing search results by how closely a title matches the
/// query -- matches the reference reading app's own real search-results screen (confirmed via
/// screenshot: 精确(0)/≥70%(2)/<70%(3248)/全部(3250) tabs with live counts), which this app's
/// search page didn't have at all before, only a sort-order toggle that reorders the same list
/// rather than letting the user filter down to just the close matches.
public enum TextSimilarity {
    /// 1.0 = identical (case-insensitive), 0.0 = nothing in common, based on normalized Levenshtein
    /// edit distance -- a plain, well-understood metric that doesn't need any book-domain-specific
    /// tuning to be a reasonable "how close is this title to what I typed" signal.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let lhs = Array(a.lowercased())
        let rhs = Array(b.lowercased())
        if lhs.isEmpty && rhs.isEmpty { return 1 }
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 1 }
        let distance = levenshteinDistance(lhs, rhs)
        return 1 - Double(distance) / Double(maxLength)
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            currentRow[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,
                    currentRow[j - 1] + 1,
                    previousRow[j - 1] + cost
                )
            }
            previousRow = currentRow
        }
        return previousRow[b.count]
    }
}
