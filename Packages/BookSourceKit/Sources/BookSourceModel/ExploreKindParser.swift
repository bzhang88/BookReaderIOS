import Foundation

/// One browsable category a source offers on its "discover" page, e.g. "玄幻" or "热门".
public struct ExploreKind: Equatable, Sendable {
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

/// Parses a `BookSource.exploreUrl`'s real-world multi-line format -- each line is either a bare
/// URL (one unnamed category) or `分类名::URL` (a name and its URL separated by "::"). Blank lines
/// are skipped. Matches real book sources' actual convention for offering multiple browsable
/// categories from a single `exploreUrl` field rather than one URL per source.
public enum ExploreKindParser {
    public static func parse(_ exploreUrl: String) -> [ExploreKind] {
        var kinds: [ExploreKind] = []
        for rawLine in exploreUrl.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let separatorRange = line.range(of: "::") {
                let name = String(line[line.startIndex..<separatorRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let url = String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !url.isEmpty else { continue }
                kinds.append(ExploreKind(name: name.isEmpty ? url : name, url: url))
            } else {
                kinds.append(ExploreKind(name: line, url: line))
            }
        }
        return kinds
    }
}
