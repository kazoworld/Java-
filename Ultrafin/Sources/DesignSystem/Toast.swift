import SwiftUI

/// A small frosted confirmation pill that slides in from the top and auto-hides
/// — used for quick "Added to My List" / "Marked as Watched" feedback so actions
/// feel acknowledged.
struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))
            Text(message)
                .font(.system(size: textSize, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }
    private var textSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}

extension View {
    /// Presents a transient toast at the top when `message` is non-nil; clears it
    /// automatically after a moment.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                ToastView(message: text)
                    .padding(.top, Spacing.xxl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2))
                        message.wrappedValue = nil
                    }
            }
        }
        .animation(.smooth(duration: 0.3), value: message.wrappedValue)
    }
}
