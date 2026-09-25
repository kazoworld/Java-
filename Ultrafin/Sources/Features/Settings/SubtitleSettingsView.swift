import SwiftUI

/// Closed-caption behavior and full subtitle appearance — font, size, color,
/// background and weight — with a live preview of exactly what playback shows.
struct SubtitleSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                preview
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Preview")
            }

            Section {
                Picker("Closed captions", selection: $settings.subtitles.captionMode) {
                    ForEach(SubtitlePreferences.CaptionMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Preferred language", selection: $settings.subtitles.preferredLanguage) {
                    ForEach(MediaLanguage.options, id: \.code) { Text($0.label).tag($0.code) }
                }
            } header: {
                Text("Closed Captions")
            } footer: {
                Text("“Off unless engaged” briefly shows captions when you skip or rewind, then hides them.")
            }

            Section {
                Picker("Font", selection: $settings.subtitles.font) {
                    ForEach(SubtitlePreferences.CaptionFont.allCases) { font in
                        // Each choice rendered in its own typeface.
                        Text(font.label)
                            .font(font.previewFont(size: fontRowSize, bold: false))
                            .tag(font)
                    }
                }
                Picker("Text size", selection: $settings.subtitles.size) {
                    ForEach(SubtitlePreferences.Size.allCases) { Text($0.label).tag($0) }
                }
                colorPicker
                Picker("Background", selection: $settings.subtitles.background) {
                    ForEach(SubtitlePreferences.Background.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Bold text", isOn: $settings.subtitles.boldText)
            } header: {
                Text("Style")
            } footer: {
                Text("Applies in both players — the black box helps captions read over bright, busy scenes.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Subtitles")
        .tint(settings.accent)
        .animation(.smooth(duration: 0.25), value: settings.subtitles.textColor)
        .animation(.smooth(duration: 0.25), value: settings.subtitles.font)
        .animation(.smooth(duration: 0.25), value: settings.subtitles.boldText)
        .animation(.smooth(duration: 0.25), value: settings.subtitles.background)
        .animation(.smooth(duration: 0.25), value: settings.subtitles.size)
    }

    /// A mock movie frame with the caption drawn exactly as playback will.
    private var preview: some View {
        let subs = settings.subtitles
        return ZStack(alignment: .bottom) {
            // A cinematic stand-in frame: deep gradient + a soft "light" blob.
            LinearGradient(colors: [Color(hex: 0x1B2340), Color(hex: 0x0A0B0F)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x6D8BFF).opacity(0.35), .clear],
                           center: .init(x: 0.75, y: 0.25), startRadius: 0, endRadius: 260)

            Text("You can't handle the truth!")
                .font(subs.font.previewFont(size: previewFontSize * CGFloat(subs.size.scalePercent) / 100,
                                            bold: subs.boldText))
                .foregroundStyle(subs.textColor.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(subs.background == .box ? Color.black.opacity(0.72) : .clear)
                .shadow(color: .black.opacity(subs.background == .box ? 0 : 0.8), radius: 2, y: 1)
                .padding(.bottom, Spacing.lg)
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous)
            .strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1))
    }

    /// Color swatches, like the accent picker — faster than a wheel for the
    /// handful of caption-safe colors.
    private var colorPicker: some View {
        HStack(spacing: Spacing.md) {
            Text("Text color")
            Spacer()
            ForEach(SubtitlePreferences.TextColor.allCases) { option in
                Button {
                    withAnimation(.smooth) { settings.subtitles.textColor = option }
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(
                            Circle().strokeBorder(
                                settings.subtitles.textColor == option
                                    ? settings.accent : .white.opacity(0.15),
                                lineWidth: settings.subtitles.textColor == option ? 3 : 1)
                        )
                        .scaleEffect(settings.subtitles.textColor == option ? 1.12 : 1)
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.18, lift: false))
                .accessibilityLabel(option.label)
            }
        }
    }

    // MARK: - Metrics

    private var previewHeight: CGFloat {
        #if os(tvOS)
        300
        #else
        170
        #endif
    }
    private var previewFontSize: CGFloat {
        #if os(tvOS)
        30
        #else
        16
        #endif
    }
    private var fontRowSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var swatchSize: CGFloat {
        #if os(tvOS)
        38
        #else
        28
        #endif
    }
}
