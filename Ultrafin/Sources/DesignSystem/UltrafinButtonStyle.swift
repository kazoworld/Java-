import SwiftUI

/// A button style that gives every tappable surface the right feel on each
/// platform:
///
/// - **tvOS:** lifts and shadows on *focus* (the Siri Remote focus engine),
///   which is the core interaction model Apple TV users expect — and exactly
///   what makes Swiftfin feel native and Moonfin feel broken on tvOS.
/// - **iOS:** a subtle press scale.
///
/// Driving focus visuals from a single style keeps the look consistent and
/// fully themeable, instead of relying on the system's default focus chrome.
struct UltrafinButtonStyle: ButtonStyle {
    var focusScale: CGFloat = 1.06
    var pressScale: CGFloat = 0.97
    /// When true, adds a soft lift shadow on focus (used by poster cards).
    var lift: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, focusScale: focusScale, pressScale: pressScale, lift: lift)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let focusScale: CGFloat
        let pressScale: CGFloat
        let lift: Bool

        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        var body: some View {
            #if os(tvOS)
            configuration.label
                .scaleEffect(scale)
                .shadow(color: .black.opacity(lift && isFocused ? 0.55 : 0),
                        radius: lift && isFocused ? 26 : 0, y: lift && isFocused ? 16 : 0)
                .zIndex(isFocused ? 1 : 0)
                .animation(.smooth(duration: 0.28), value: isFocused)
                .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            #else
            configuration.label
                .scaleEffect(configuration.isPressed ? pressScale : 1)
                .animation(.smooth(duration: 0.14), value: configuration.isPressed)
            #endif
        }

        #if os(tvOS)
        private var scale: CGFloat {
            if configuration.isPressed { return pressScale }
            return isFocused ? focusScale : 1
        }
        #endif
    }
}

extension View {
    /// Convenience for the poster/card focus treatment.
    func mediaCardButtonStyle() -> some View {
        buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
    }
}
