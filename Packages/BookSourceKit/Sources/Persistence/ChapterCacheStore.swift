import Foundation
import WebBookOrchestrator

/// Caches fetched chapter content on disk for offline reading -- deliberately opt-in (only
/// populated by an explicit "download" action, never automatically on every read) so normal
/// browsing doesn't silently grow storage for chapters the user only glanced at once. One JSON
/// file per book (keyed by a stable hash of its `bookUrl`, since URLs contain characters that
/// aren't safe filenames), holding a chapter-index -> content map -- caching raw fetched content
/// rather than post-replace-rule text so newly added purification rules still apply to already
/// -downloaded chapters when read.
public actor ChapterCacheStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func chapter(bookUrl: String, index: Int) async throws -> ChapterContent? {
        try await loadBook(bookUrl)[index]
    }

    public func save(bookUrl: String, index: Int, content: ChapterContent) async throws {
        var chapters = try await loadBook(bookUrl)
        chapters[index] = content
        try saveBook(bookUrl, chapters)
    }

    public func downloadedIndices(bookUrl: String) async throws -> Set<Int> {
        Set(try await loadBook(bookUrl).keys)
    }

    public func removeBook(bookUrl: String) async throws {
        try? FileManager.default.removeItem(at: fileURL(for: bookUrl))
    }

    // MARK: - Per-book file I/O

    private func loadBook(_ bookUrl: String) async throws -> [Int: ChapterContent] {
        let url = fileURL(for: bookUrl)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return try JSONDecoder().decode([Int: ChapterContent].self, from: data)
    }

    private func saveBook(_ bookUrl: String, _ chapters: [Int: ChapterContent]) throws {
        let data = try JSONEncoder().encode(chapters)
        try data.write(to: fileURL(for: bookUrl), options: .atomic)
    }

    private func fileURL(for bookUrl: String) -> URL {
        directory.appendingPathComponent("\(Self.stableHash(bookUrl)).json")
    }

    /// FNV-1a -- deterministic across launches (unlike Swift's built-in `Hasher`, which is
    /// randomly seeded per process to resist hash-flooding, and so isn't suitable for anything
    /// that needs to name the same file the same way every time).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
