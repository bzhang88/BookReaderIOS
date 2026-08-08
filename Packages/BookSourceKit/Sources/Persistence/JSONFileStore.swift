import Foundation

/// A generic Codable-value-in-a-JSON-file store. `actor`-isolated so concurrent reads/writes from
/// different app contexts (e.g. a background TOC refresh and a UI progress update) don't race.
///
/// Deliberately FileManager/JSON rather than SwiftData for v1: SwiftData is an Apple-only
/// framework (like JavaScriptCore, it won't compile on this Windows dev machine at all), and the
/// plan's own reasoning for using plain JSON early — the data model is still easy to inspect and
/// needs no migration ceremony — still applies. Migrate to SwiftData once there's real Mac access
/// to build/verify it against.
public actor JSONFileStore<T: Codable> {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(T.self, from: data)
    }

    public func save(_ value: T) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
