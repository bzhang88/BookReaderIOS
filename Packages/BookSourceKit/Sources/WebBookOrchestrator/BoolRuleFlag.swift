import Foundation

extension Optional where Wrapped == String {
    /// Legado's `.isTrue()` convention for flag-style rule fields (`isVolume`/`isVip`/`isPay`):
    /// blank/nil/"null" -> false; case-insensitive false/no/not/0/0.0 -> false; anything else -> true.
    public func isTrueFlag() -> Bool {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return false
        }
        let lowered = value.lowercased()
        if lowered == "null" { return false }
        return !["false", "no", "not", "0", "0.0"].contains(lowered)
    }
}
