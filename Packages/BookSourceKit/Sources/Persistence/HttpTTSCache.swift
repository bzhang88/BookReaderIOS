import Foundation

/// Pre-generated audio cache for `HttpTTSEngine` output -- confirmed against Legado_Max's real
/// `HttpReadAloudService` that it keeps a size-capped disk cache (their Media3 `SimpleCache` with a
/// 128MB LRU evictor) rather than caching forever, so repeated playback of the same paragraph
/// doesn't keep re-hitting the network/API, but storage still has a ceiling. Keyed by
/// `engineID + text` (not just text) since the same paragraph read by two different engines
/// produces different audio.
public actor HttpTTSCache {
    private let directory: URL
    private let maxTotalBytes: Int64

    public init(directory: URL, maxTotalBytes: Int64 = 100 * 1024 * 1024) {
        self.directory = directory
        self.maxTotalBytes = maxTotalBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Touches the file's modification date on a hit so LRU eviction treats it as recently used --
    /// without this, a frequently-replayed paragraph would still be evicted first just because it
    /// was originally *written* longest ago.
    public func cachedFileURL(engineID: String, text: String) -> URL? {
        let url = fileURL(engineID: engineID, text: text)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    public func store(engineID: String, text: String, audio: Data) async throws -> URL {
        let url = fileURL(engineID: engineID, text: text)
        try audio.write(to: url, options: .atomic)
        evictIfNeeded()
        return url
    }

    public func totalSizeBytes() -> Int64 {
        fileInfos().reduce(0) { $0 + $1.size }
    }

    public func removeAll() throws {
        for info in fileInfos() {
            try? FileManager.default.removeItem(at: info.url)
        }
    }

    private func evictIfNeeded() {
        let toEvict = Self.filesToEvict(files: fileInfos(), maxTotalBytes: maxTotalBytes)
        for url in toEvict {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Pure and separately testable -- given every cached file's size/mtime and a byte budget,
    /// returns the oldest-first subset to delete to get back under budget. Real filesystem I/O
    /// (`evictIfNeeded`) is just this function plus gathering/applying the result.
    static func filesToEvict(files: [(url: URL, modifiedAt: Date, size: Int64)], maxTotalBytes: Int64) -> [URL] {
        let totalSize = files.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > maxTotalBytes else { return [] }
        let oldestFirst = files.sorted { $0.modifiedAt < $1.modifiedAt }
        var remaining = totalSize
        var toEvict: [URL] = []
        for file in oldestFirst {
            guard remaining > maxTotalBytes else { break }
            toEvict.append(file.url)
            remaining -= file.size
        }
        return toEvict
    }

    private func fileInfos() -> [(url: URL, modifiedAt: Date, size: Int64)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate, let size = values.fileSize else { return nil }
            return (url, modifiedAt, Int64(size))
        }
    }

    private func fileURL(engineID: String, text: String) -> URL {
        directory.appendingPathComponent("\(Self.stableHash(engineID + "|" + text)).audio")
    }

    /// Same FNV-1a scheme `ChapterCacheStore` uses -- deterministic across launches, unlike Swift's
    /// randomly-seeded `Hasher`.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
