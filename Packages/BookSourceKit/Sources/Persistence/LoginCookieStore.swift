import Foundation

/// One cookie captured from a book source's WebView login, in a plain Codable shape -- the
/// platform's own `HTTPCookie` type isn't `Codable`, so this is the bridge between a WebView's
/// live cookie jar and this app's JSON-file persistence.
public struct SavedCookie: Codable, Equatable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var isSecure: Bool
    public var expiresAt: Date?

    public init(name: String, value: String, domain: String, path: String, isSecure: Bool, expiresAt: Date?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.expiresAt = expiresAt
    }
}

/// Persists the cookies captured from a book source's WebView login, keyed by `bookSourceUrl`, so
/// a login survives an app relaunch. `URLSessionHTTPClient` picks these up for free once they're
/// re-injected into `HTTPCookieStorage.shared` at launch -- its underlying `URLSession.shared`
/// already replays cookies from that shared storage on every request automatically, so no changes
/// are needed to the networking code itself, only to when/where cookies get written into it.
public actor LoginCookieStore {
    private let store: JSONFileStore<[String: [SavedCookie]]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func cookies(bookSourceUrl: String) async throws -> [SavedCookie] {
        (try await store.load() ?? [:])[bookSourceUrl] ?? []
    }

    public func setCookies(_ cookies: [SavedCookie], bookSourceUrl: String) async throws {
        var all = try await store.load() ?? [:]
        if cookies.isEmpty {
            all.removeValue(forKey: bookSourceUrl)
        } else {
            all[bookSourceUrl] = cookies
        }
        try await store.save(all)
    }

    public func isLoggedIn(bookSourceUrl: String) async throws -> Bool {
        !(try await cookies(bookSourceUrl: bookSourceUrl)).isEmpty
    }

    /// Everything ever saved, across all sources -- used once at app launch to repopulate
    /// `HTTPCookieStorage.shared` (a WebView's cookie jar and `URLSession`'s are separate stores on
    /// iOS, so this hand-off has to happen explicitly rather than being automatic).
    public func allCookies() async throws -> [String: [SavedCookie]] {
        try await store.load() ?? [:]
    }
}
