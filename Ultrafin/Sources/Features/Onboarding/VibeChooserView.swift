import SwiftUI

/// The first thing after sign-in: "What's the vibe?" — two glass orbs, Media or
/// Music, that open two separate experiences. A quiet toggle underneath makes
/// the pick the app's default so the question stops being asked.
///
/// Everything sizes off the available space, so it reads correctly from an
/// iPhone SE to a 4K TV, and the whole thing arrives on a short spring cascade.
struct VibeChooserView: View {
    /// Called with the experience the user picked.
    let onPick: (AppMode) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var appeared = false
    @State private var chosen: AppMode?
    @State private var setAsDefault = false
    #if os(tvOS)
    @FocusState private var focus: Focus?
    private enum Focus: Hashable { case mode(AppMode), remember }
    #endif

    var body: some View {
        GeometryReader { geo in
            let scale = ResponsiveScale(size: geo.size)
            ZStack {
                UltrafinMeshBackdrop()
                // Deepen the mesh so the orbs read as the hero.
                Color.black.opacity(0.28).ignoresSafeArea()

                VStack(spacing: scale(46)) {
                    headline(scale)
                    orbs(scale)
                    rememberToggle(scale)
                }
                .padding(.horizontal, scale(28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) { appeared = true }
            #if os(tvOS)
            focus = .mode(.media)
            #endif
        }
    }

    // MARK: - Pieces

    private func headline(_ scale: ResponsiveScale) -> some View {
        VStack(spacing: scale(8)) {
            Text("What's the vibe?")
                .font(.system(size: scale(34), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Two experiences, kept separate. Switch anytime.")
                .font(.system(size: scale(16), weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : scale(16))
    }

    @ViewBuilder
    private func orbs(_ scale: ResponsiveScale) -> some View {
        let media = orb(.media, title: "Media", subtitle: "Movies & shows",
                        icon: "film.stack.fill",
                        colors: [Color(hex: 0x2B32B2), Color(hex: 0x1488CC)],
                        scale: scale)
        let music = orb(.music, title: "Music", subtitle: "Albums & playlists",
                        icon: "music.note",
                        colors: [Color(hex: 0x8E2DE2), Color(hex: 0xE94057)],
                        scale: scale)
        // Side by side normally; stacked when a landscape phone leaves no height.
        HStack(spacing: scale(34)) {
            media
            music
        }
        .frame(maxWidth: .infinity)
    }

    private func orb(_ vibe: AppMode, title: String, subtitle: String,
                     icon: String, colors: [Color], scale: ResponsiveScale) -> some View {
        let isChosen = chosen == vibe
        #if os(tvOS)
        let isFocused = focus == .mode(vibe)
        #else
        let isFocused = false
        #endif
        let side = orbSide(scale)
        return Button {
            pick(vibe)
        } label: {
            VStack(spacing: scale(16)) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.25), .clear],
                                             startPoint: .top, endPoint: .center))
                    Image(systemName: icon)
                        .font(.system(size: side * 0.3, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(.white.opacity(isFocused ? 0.9 : 0.25),
                                               lineWidth: isFocused ? 4 : 1))
                .shadow(color: colors.first?.opacity(isFocused || isChosen ? 0.7 : 0.4) ?? .clear,
                        radius: isFocused || isChosen ? 40 : 24, y: 14)
                .scaleEffect(isChosen ? 1.12 : (isFocused ? 1.06 : 1))

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: scale(20), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: scale(13), weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focused($focus, equals: .mode(vibe))
        #endif
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.85)
        .animation(.spring(duration: 0.6, bounce: 0.3).delay(vibe == .media ? 0.05 : 0.14), value: appeared)
        .animation(.spring(duration: 0.5, bounce: 0.4), value: chosen)
        #if os(tvOS)
        .animation(.smooth(duration: 0.2), value: focus)
        #endif
    }

    /// "Start here every time" — makes the pick the app's launch default.
    private func rememberToggle(_ scale: ResponsiveScale) -> some View {
        #if os(tvOS)
        let isFocused = focus == .remember
        #else
        let isFocused = false
        #endif
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { setAsDefault.toggle() }
            Haptics.play(.selection)
        } label: {
            HStack(spacing: scale(10)) {
                Image(systemName: setAsDefault ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: scale(19), weight: .semibold))
                    .foregroundStyle(setAsDefault ? settings.theme.accent.color : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                Text("Start here every time")
                    .font(.system(size: scale(15), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(setAsDefault ? 0.95 : 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, scale(20))
            .padding(.vertical, scale(11))
            .glassCapsule(dim: setAsDefault ? 0.16 : 0.06)
            .overlay(
                Capsule().strokeBorder(isFocused ? .white.opacity(0.85) : .clear,
                                       lineWidth: isFocused ? 3 : 0)
            )
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focused($focus, equals: .remember)
        #endif
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : scale(14))
        .animation(.spring(duration: 0.6, bounce: 0.25).delay(0.22), value: appeared)
        .accessibilityLabel("Start in this experience every time")
        .accessibilityAddTraits(setAsDefault ? [.isSelected] : [])
    }

    // MARK: - Behavior

    private func pick(_ vibe: AppMode) {
        guard chosen == nil else { return }
        Haptics.play(.success)
        if setAsDefault { StartupPreference.set(.launch(vibe)) }
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { chosen = vibe }
        // Let the pop play, then hand control to the app.
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            onPick(vibe)
        }
    }

    private func orbSide(_ scale: ResponsiveScale) -> CGFloat {
        #if os(tvOS)
        scale(300)
        #else
        // Never wider than half the screen minus the gap.
        min(scale(150), (scale.size.width - scale(90)) / 2)
        #endif
    }
}
