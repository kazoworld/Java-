import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Stable per-install identifiers reported to Jellyfin so the server can track
/// this device in its session list.
enum DeviceIdentity {
    private static let storageKey = "com.ultrafin.deviceID"

    /// A UUID generated once per install and persisted in `UserDefaults`.
    static var persistentID: String {
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: storageKey)
        return new
    }

    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Ultrafin Device"
        #endif
    }
}
