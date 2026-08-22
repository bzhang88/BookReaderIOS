import Foundation

/// A lightweight name+author(+intro) projection of a shelf book -- the portable "书单" (reading
/// list) format Legado_Max's own `BookshelfViewModel.exportBookshelf`/`importBookshelf` use,
/// deliberately smaller than a full shelf/backup entry (no source URL, no reading progress) since
/// sharing a reading list across devices is the whole point: importing re-resolves each title
/// against whichever sources the *importing* device already has configured, rather than assuming
/// the exporting device's exact source URLs exist there too.
public struct ShelfListEntry: Codable, Equatable, Sendable {
    public var name: String
    public var author: String?
    public var intro: String?

    public init(name: String, author: String? = nil, intro: String? = nil) {
        self.name = name
        self.author = author
        self.intro = intro
    }
}

public enum ShelfListFormat {
    public static func encode(_ entries: [ShelfListEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries), let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// `nil` when `text` doesn't even parse as a JSON array of `{name, author, intro}` objects --
    /// lets the caller show "格式不对" up front (matching Legado's own `importBookshelf` behavior)
    /// rather than silently importing zero books.
    public static func decode(_ text: String) -> [ShelfListEntry]? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ShelfListEntry].self, from: data)
    }
}
