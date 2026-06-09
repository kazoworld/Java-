import SwiftUI

/// Settings hub. Each row uses a tinted icon tile + description so the page
/// reads as a premium, scannable list, and drills into a focused sub-page.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                NavigationLink { AppearanceSettingsView() } label: {
                    SettingsRowLabel(title: "Appearance", subtitle: "Theme, accent, cards, display",
                                     systemImage: "paintbrush.fill", tint: .purple)
                }
                NavigationLink { FeaturedSettingsView() } label: {
                    SettingsRowLabel(title: "Media Bar", subtitle: "Featured banner on Home",
                                     systemImage: "rectangle.on.rectangle.angled.fill", tint: .pink)
                }
                NavigationLink { HomeLayoutEditorView() } label: {
                    SettingsRowLabel(title: "Home Layout", subtitle: "Reorder and show/hide rows",
                                     systemImage: "rectangle.3.group.fill", tint: .blue)
                }
                NavigationLink { PlaybackSettingsView() } label: {
                    SettingsRowLabel(title: "Playback", subtitle: "Engine, video, audio, subtitles",
                                     systemImage: "play.rectangle.fill", tint: .orange)
                }
            }

            Section {
                NavigationLink { AccountSettingsView() } label: {
                    SettingsRowLabel(title: "Account", subtitle: "Server and sign out",
                                     systemImage: "person.crop.circle.fill", tint: .teal)
                }
            }

            Section {
                LabeledContent("Ultrafin", value: "1.0.0")
                LabeledContent("Playback core",
                               value: VLCPlaybackEngine.isAvailable ? "AVFoundation + VLCKit" : "AVFoundation")
            } header: {
                Text("About")
            } footer: {
                Text("Ultrafin is a Jellyfin client. Jellyfin and the Swiftfin media core are open source.")
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Settings")
        .tint(settings.theme.accent.color)
    }
}

/// A premium list row: a rounded, tinted icon tile with a title and one-line
/// description.
struct SettingsRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: tileSize, height: tileSize)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: tileSize * 0.27, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(subtitle)
                    .font(.system(size: subtitleSize))
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var tileSize: CGFloat {
        #if os(tvOS)
        56
        #else
        34
        #endif
    }
    private var iconSize: CGFloat {
        #if os(tvOS)
        26
        #else
        17
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        30
        #else
        17
        #endif
    }
    private var subtitleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        13
        #endif
    }
}
