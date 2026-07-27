import SwiftUI

/// A frosted, floating glass panel that holds an auth form. Soft gradient
/// stroke + drop shadow give it the "liquid glass" lift over the ambient.
struct AuthCard<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Spacing.lg) { content }
            .padding(Spacing.xxl)
            .frame(maxWidth: 480)
            // Real Liquid Glass + the brand rim — the first surface a new user
            // ever sees should be the most premium one. Calm and still: one soft
            // depth shadow and a whisper of accent, no pulsing.
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(LiquidGlass.rim(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
            .shadow(color: settings.theme.accent.color.opacity(0.18), radius: 34, y: 8)
    }
}

/// Branded header. With no `systemImage` it leads with the real Ultrafin glass
/// mark (the app identity); pass a symbol for sub-flows like Sign In / Quick
/// Connect, shown as a clean glass chip rather than a heavy blurred glow.
struct AuthBrand: View {
    var systemImage: String? = nil
    let title: String
    let subtitle: String

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: chipGlyph, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: chipSize, height: chipSize)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: chipSize * 0.28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: chipSize * 0.28, style: .continuous)
                        .strokeBorder(LiquidGlass.rim(0.7), lineWidth: 1))
                    .shadow(color: settings.theme.accent.color.opacity(0.35), radius: 16, y: 6)
            } else {
                UltrafinMark(size: markSize)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(Typography.displayTitle)
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var markSize: CGFloat {
        #if os(tvOS)
        128
        #else
        88
        #endif
    }
    private var chipSize: CGFloat {
        #if os(tvOS)
        100
        #else
        68
        #endif
    }
    private var chipGlyph: CGFloat {
        #if os(tvOS)
        46
        #else
        32
        #endif
    }
}

/// A glass text field with a leading icon. Handles secure entry, the URL
/// keyboard, submit, and optional auto-focus.
struct GlassField: View {
    enum Keyboard { case `default`, url }

    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: Keyboard = .default
    var submitLabel: SubmitLabel = .done
    var autofocus: Bool = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(focused ? UltrafinColors.accent : UltrafinColors.secondaryText)
                .frame(width: 26)
            field
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(focused ? UltrafinColors.accent.opacity(0.8) : .white.opacity(0.12),
                                   lineWidth: focused ? 2 : 1)
        )
        .animation(.smooth(duration: 0.2), value: focused)
        .onAppear { if autofocus { focused = true } }
    }

    @ViewBuilder
    private var field: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(UltrafinColors.primaryText)
        .focused($focused)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboard == .url ? .URL : .default)
        #endif
    }
}
