import SwiftUI

/// The first thing after sign-in: "What's the vibe?" — two glass orbs, Media or
/// Music, that route the app to Home or the Music tab. Fluid, focus-friendly on
/// tvOS, tap/press on iOS.
struct VibeChooserView: View {
    /// Called with the tab index to land on: 0 = Media (Home), 2 = Music.
    let onPick: (Int) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var appeared = false
    @State private var chosen: Vibe?
    #if os(tvOS)
    @FocusState private var focus: Vibe?
    #endif

    private enum Vibe: Hashable { case media, music }

    var body: some View {
        ZStack {
            UltrafinMeshBackdrop()
            // Deepen the mesh so the orbs read as the hero.
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: headlineGap) {
                VStack(spacing: Spacing.sm) {
                    Text("What's the vibe?")
                        .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("You can switch anytime.")
                        .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                HStack(spacing: orbGap) {
                    orb(.media, title: "Media", subtitle: "Movies & shows",
                        icon: "film.stack.fill",
                        colors: [Color(hex: 0x2B32B2), Color(hex: 0x1488CC)])
                    orb(.music, title: "Music", subtitle: "Albums & playlists",
                        icon: "music.note",
                        colors: [Color(hex: 0x8E2DE2), Color(hex: 0xE94057)])
                }
            }
            .padding(Spacing.xxl)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) { appeared = true }
            #if os(tvOS)
            focus = .media
            #endif
        }
    }

    private func orb(_ vibe: Vibe, title: String, subtitle: String,
                     icon: String, colors: [Color]) -> some View {
        let isChosen = chosen == vibe
        #if os(tvOS)
        let isFocused = focus == vibe
        #else
        let isFocused = false
        #endif
        return Button {
            pick(vibe)
        } label: {
            VStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.25), .clear],
                                             startPoint: .top, endPoint: .center))
                    Image(systemName: icon)
                        .font(.system(size: orbSize * 0.3, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .frame(width: orbSize, height: orbSize)
                .overlay(Circle().strokeBorder(.white.opacity(isFocused ? 0.9 : 0.25),
                                               lineWidth: isFocused ? 4 : 1))
                .shadow(color: colors.first?.opacity(isFocused || isChosen ? 0.7 : 0.4) ?? .clear,
                        radius: isFocused || isChosen ? 40 : 24, y: 14)
                .scaleEffect(isChosen ? 1.12 : (isFocused ? 1.06 : 1))

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: labelSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: labelSize * 0.62, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focused($focus, equals: vibe)
        #endif
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.85)
        .animation(.spring(duration: 0.6, bounce: 0.3).delay(vibe == .media ? 0.05 : 0.14), value: appeared)
        .animation(.spring(duration: 0.5, bounce: 0.4), value: chosen)
        #if os(tvOS)
        .animation(.smooth(duration: 0.2), value: focus)
        #endif
    }

    private func pick(_ vibe: Vibe) {
        guard chosen == nil else { return }
        Haptics.play(.success)
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { chosen = vibe }
        // Let the pop play, then hand control to the app.
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            onPick(vibe == .media ? 0 : 2)
        }
    }

    // MARK: - Metrics

    private var orbSize: CGFloat {
        #if os(tvOS)
        320
        #else
        150
        #endif
    }
    private var orbGap: CGFloat {
        #if os(tvOS)
        Spacing.xxl * 1.5
        #else
        Spacing.xl
        #endif
    }
    private var headlineGap: CGFloat {
        #if os(tvOS)
        Spacing.xxl * 1.6
        #else
        Spacing.xxl
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        64
        #else
        34
        #endif
    }
    private var subtitleSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var labelSize: CGFloat {
        #if os(tvOS)
        30
        #else
        20
        #endif
    }
}
