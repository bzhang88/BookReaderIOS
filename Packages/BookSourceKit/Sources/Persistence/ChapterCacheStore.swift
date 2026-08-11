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

    /// On-disk size of one book's cache file -- 0 if it was never downloaded (rather than throwing,
    /// since "no cache yet" is a totally normal state for a storage-management screen to show).
    public func sizeBytes(bookUrl: String) async -> Int64 {
        Self.fileSize(at: fileURL(for: bookUrl))
    }

    /// Sums every file under the cache directory -- used for the storage-management screen's
    /// overall "缓存占用" figure without requiring the caller to already know every book that's
    /// ever been downloaded.
    public func totalSizeBytes() async -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return files.reduce(Int64(0)) { $0 + Self.fileSize(at: $1) }
    }

    /// Wipes every book's downloaded chapter cache in one go -- the "清空全部下载缓存" action.
    /// Purely a storage reclaim; doesn't touch the shelf/local-book lists themselves, so cleared
    /// books just go back to fetching over the network next time they're read.
    public func removeAll() async throws {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
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
