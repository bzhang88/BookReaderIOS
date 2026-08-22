import Foundation

/// Optional shared-token gate for `LANWebServer` -- confirmed against Legado_Max's own
/// `AppConfig.webServiceAuthEnabled`/`webServiceToken` (`HttpServer.kt`) that a real LAN reading
/// server should be able to require this before serving anything: without it, any device on the
/// same Wi-Fi/LAN can browse a user's full shelf and read complete book text with zero
/// authentication, a real information-disclosure gap on a shared/public network (a coffee-shop
/// Wi-Fi, a university dorm network, ...), not just a private home LAN. Pure/stateless -- there's
/// no session or cookie, `LANWebServer` doesn't keep connections alive across requests (see its own
/// doc comment), so every request re-proves the token via its own query string instead.
public enum LANWebAuth {
    /// `requiredToken` empty or `nil` means auth is off (the default, matching this feature's
    /// pre-existing no-auth behavior so enabling it is opt-in, not a breaking change for anyone
    /// already using it on a network they trust).
    public static func isAuthorized(request: SimpleHTTPRequest, requiredToken: String?) -> Bool {
        guard let requiredToken, !requiredToken.isEmpty else { return true }
        return request.query["token"] == requiredToken
    }
}
