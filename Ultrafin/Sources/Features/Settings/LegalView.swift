import SwiftUI

/// Legal & attribution — makes plain that Ultrafin is only a player shell and
/// credits the open-source projects it stands on.
struct LegalView: View {
    @Environment(SettingsStore.self) private var settings

    private let jellyfinURL = URL(string: "https://github.com/jellyfin/jellyfin")!
    private let swiftfinURL = URL(string: "https://github.com/jellyfin/Swiftfin")!
    private let vlcURL = URL(string: "https://code.videolan.org/videolan/VLCKit")!

    var body: some View {
        Form {
            Section {
                Text("""
                Ultrafin is an independent client — a shell that connects to and \
                displays media from a Jellyfin server you own and control. It \
                hosts your content; it does not provide, stream, or distribute \
                any media itself.

                All movies, shows, music, and metadata come from your own \
                Jellyfin server. Ultrafin stores nothing centrally and is not \
                affiliated with, endorsed by, or sponsored by the Jellyfin \
                project. You are responsible for the content on your server and \
                for complying with the laws of your region.
                """)
                .font(.system(size: bodySize))
                .foregroundStyle(UltrafinColors.secondaryText)
                .lineSpacing(4)
                .tvFocusable()
            } header: {
                Text("About This App")
            }

            Section {
                linkRow(title: "Jellyfin", subtitle: "The open-source media server (GPL-2.0)",
                        systemImage: "server.rack", url: jellyfinURL)
                linkRow(title: "Swiftfin", subtitle: "Jellyfin's open-source Apple clients (MPL-2.0)",
                        systemImage: "swift", url: swiftfinURL)
                linkRow(title: "VLCKit", subtitle: "The media playback engine (LGPL-2.1)",
                        systemImage: "play.rectangle.fill", url: vlcURL)
            } header: {
                Text("Open Source")
            } footer: {
                Text("Ultrafin is built on open-source software. Jellyfin is free software — explore or run your own server from its GitHub.")
            }

            Section {
                Text("""
                Ultrafin is provided “as is,” without warranty of any kind. The \
                trademarks “Jellyfin” and “VLC” belong to their respective \
                owners and are used here only to describe compatibility.
                """)
                .font(.system(size: bodySize * 0.9))
                .foregroundStyle(UltrafinColors.tertiaryText)
                .lineSpacing(3)
                .tvFocusable()
            } header: {
                Text("Disclaimer")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Legal")
        .tint(settings.accent)
    }

    @ViewBuilder
    private func linkRow(title: String, subtitle: String, systemImage: String, url: URL) -> some View {
        #if os(tvOS)
        // No browser on the TV — show the URL to type on another device.
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(settings.accent)
                .frame(width: iconSize + 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: rowTitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(subtitle)
                    .font(.system(size: rowTitleSize * 0.7))
                    .foregroundStyle(UltrafinColors.secondaryText)
                Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(.system(size: rowTitleSize * 0.7, weight: .medium, design: .monospaced))
                    .foregroundStyle(settings.accent)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .tvFocusable()
        #else
        Link(destination: url) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(settings.accent)
                    .frame(width: iconSize + 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: rowTitleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text(subtitle)
                        .font(.system(size: rowTitleSize * 0.75))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: rowTitleSize * 0.8, weight: .semibold))
                    .foregroundStyle(UltrafinColors.tertiaryText)
            }
        }
        #endif
    }

    private var bodySize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
    private var rowTitleSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var iconSize: CGFloat {
        #if os(tvOS)
        26
        #else
        18
        #endif
    }
}
