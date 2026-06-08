import SwiftUI

// MARK: - Glass surface

/// A frosted, slightly elevated container used for cards, sheets and controls.
/// The material + thin stroke reads as "glass" without expensive blur on tvOS.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Spacing.cornerRadius) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(settings.theme.accent.color, in: RoundedRectangle(cornerRadius: Spacing.md, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
        .disabled(isLoading)
    }
}

// MARK: - Async image with graceful placeholder

/// Lightweight remote image loader with an in-memory cache and a shimmering
/// placeholder, so scrolling grids never block the main thread on decode.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder.overlay(Image(systemName: "photo").foregroundStyle(UltrafinColors.tertiaryText))
            case .empty:
                placeholder.shimmer()
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        UltrafinColors.elevatedSurface
    }
}

// MARK: - Shimmer

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.5)
                .offset(x: phase * geo.size.width * 1.5)
            }
            .mask(Rectangle())
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
