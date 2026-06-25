import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lightweight haptic feedback. A no-op on tvOS (no Taptic Engine), so call sites
/// stay platform-agnostic — fire it on confirmations and key transport actions to
/// make the iOS app feel tactile and responsive.
enum Haptics {
    enum Feedback {
        case light, medium, soft, rigid
        case success, warning
        case selection
    }

    static func play(_ feedback: Feedback) {
        #if os(iOS)
        switch feedback {
        case .light:  UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .soft:   UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .rigid:  UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}
