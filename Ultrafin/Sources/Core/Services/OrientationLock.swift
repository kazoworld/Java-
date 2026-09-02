#if os(iOS)
import UIKit

/// iPhone orientation policy: the whole app is portrait-only, EXCEPT while a
/// video is playing — the player unlocks rotation so movies can go landscape.
///
/// The `UIApplicationDelegateAdaptor` in `UltrafinApp` routes the system's
/// supported-orientations query through `mask`; the player flips it on
/// appear/disappear via `unlockForPlayback()` / `lockPortrait()`.
final class OrientationLock: NSObject, UIApplicationDelegate {
    /// What the app currently allows. Portrait everywhere by default.
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }

    /// Allow every orientation (video playback).
    static func unlockForPlayback() {
        mask = .allButUpsideDown
        refresh()
    }

    /// Back to portrait-only, actively rotating the UI upright if the phone is
    /// currently landscape.
    static func lockPortrait() {
        mask = .portrait
        refresh(request: .portrait)
    }

    private static func refresh(request: UIInterfaceOrientationMask? = nil) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        if let request {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: request))
        }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
#endif
