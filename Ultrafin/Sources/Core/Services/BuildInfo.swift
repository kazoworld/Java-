import Foundation

/// A human-readable marker for the build that's actually running.
///
/// Xcode will happily launch the previously-installed app when a build fails,
/// which makes "is this the new code?" surprisingly hard to answer from the
/// screen. Bump `marker` whenever a change needs to be visually confirmed on
/// device, and read it in Music → Settings.
enum BuildInfo {
    /// Increment on each round of UI work worth verifying on hardware.
    static let marker = "resume+playlists+carplay"

    /// The bundle's own version/build, for completeness.
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
