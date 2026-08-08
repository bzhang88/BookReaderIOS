import Foundation

/// Configuration for a third-party AI API provider (OpenAI-compatible or similar) -- the API key
/// itself is deliberately not a stored property here; it lives in Keychain (see the app-layer
/// KeychainStore), keyed by `id`, so it never round-trips through this Codable/JSON-file-backed
/// struct.
public struct AIProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var modelName: String
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString, name: String, baseURL: String, modelName: String, enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelName = modelName
        self.enabled = enabled
    }
}
