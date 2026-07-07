import SwiftUI

/// A frosted, floating glass panel that holds an auth form. Soft gradient
/// stroke + drop shadow give it the "liquid glass" lift over the ambient.
struct AuthCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Spacing.lg) { content }
            .padding(Spacing.xl)
            .frame(maxWidth: 520)
            // Real Liquid Glass + the brand rim — the first surface a new user
            // ever sees should be the most premium one.
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(LiquidGlass.rim(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 34, y: 18)
    }
}

/// Branded header: a glowing accent glyph + title + subtitle.
struct AuthBrand: View {
    var systemImage: String = "play.circle.fill"
    let title: String
    let subtitle: String

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(settings.theme.accent.color.opacity(0.35))
                    .frame(width: 130, height: 130)
                    .blur(radius: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 66, weight: .thin))
                    .foregroundStyle(UltrafinColors.accentGradient)
            }
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
