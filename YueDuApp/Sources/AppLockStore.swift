import Foundation

/// Local app-access password -- entirely on-device, unrelated to the WebDAV backup credentials
/// (those protect a cloud account; this protects "someone else picks up my unlocked phone").
/// Presence of a stored password *is* "lock enabled" -- there's no separate enabled flag that
/// could fall out of sync with it.
enum AppLockStore {
    private static let key = "app.lockPassword"
    private static let biometricKey = "app.lockBiometricEnabled"

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
        setBiometricEnabled(false)
    }

    /// Whether Face ID/Touch ID should be offered as a shortcut past `AppLockView`'s password
    /// field. Meaningless (and always read back `false`) while `isEnabled` is `false` -- there's no
    /// separate biometric-only lock mode, only "skip retyping the password lock's own password".
    /// Plain `UserDefaults`, not Keychain: this is a preference flag, not a secret.
    static var isBiometricEnabled: Bool {
        isEnabled && UserDefaults.standard.bool(forKey: biometricKey)
    }

    static func setBiometricEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricKey)
    }
}
