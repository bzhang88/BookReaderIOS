import Foundation

/// Local app-access password -- entirely on-device, unrelated to the WebDAV backup credentials
/// (those protect a cloud account; this protects "someone else picks up my unlocked phone").
/// Presence of a stored password *is* "lock enabled" -- there's no separate enabled flag that
/// could fall out of sync with it.
enum AppLockStore {
    private static let key = "app.lockPassword"

    static var isEnabled: Bool { KeychainStore.get(key) != nil }

    static func setPassword(_ password: String) {
        KeychainStore.set(password, forKey: key)
    }

    /// No password configured means nothing to verify against -- returns true so callers that
    /// unconditionally gate on this (rather than checking `isEnabled` first) fail open, not closed.
    static func verify(_ password: String) -> Bool {
        guard let stored = KeychainStore.get(key) else { return true }
        return stored == password
    }

    static func disable() {
        KeychainStore.delete(key)
    }
}
