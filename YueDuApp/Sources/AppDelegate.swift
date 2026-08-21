import UIKit

/// The single reason this app has a `UIApplicationDelegate` at all: `application(_:
/// supportedInterfaceOrientationsFor:)` is the one hook UIKit consults for allowed orientations on a
/// pure-SwiftUI `App`/`Scene` (there's no SwiftUI-native equivalent). Wired in via
/// `@UIApplicationDelegateAdaptor` in `YueDuApp.swift`. See `OrientationLock`'s doc comment
/// (`ReaderTheme.swift`) for the full mechanism this participates in.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
