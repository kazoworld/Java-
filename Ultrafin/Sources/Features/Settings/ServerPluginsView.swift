import SwiftUI

/// The server's installed plugins, with badges for the ones Ultrafin actively
/// integrates with. Jellyfin plugins run ON THE SERVER — the app "supports"
/// them by consuming the APIs they expose, automatically, when detected.
struct ServerPluginsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var plugins: [InstalledPlugin] = []
    @State private var isLoading = true

    /// What Ultrafin does with a recognized plugin, matched loosely by name.
    private static let integrations: [(keywords: [String], benefit: String)] = [
        (["intro skipper"], "Powers Skip Intro & Skip Credits"),
        (["media segments", "chapter segments", "edl"], "Powers Skip Intro & Skip Credits"),
        (["trickplay", "jellyscrub"], "Scrubber preview thumbnails"),
        (["open subtitles", "opensubtitles", "subtitle"], "Subtitle downloads on the server"),
        (["playback reporting"], "Watch statistics (server dashboard)"),
        (["fanart", "tmdb", "themerr", "studio images"], "Richer artwork & metadata"),
        (["merge versions"], "Cleaner libraries (single entries)"),
        (["auto organize", "library cleaner"], "Tidier libraries, automatically")
    ]

    private func benefit(for plugin: InstalledPlugin) -> String? {
        let name = plugin.name.lowercased()
        return Self.integrations.first { entry in
            entry.keywords.contains { name.contains($0) }
        }?.benefit
    }

    private var enhancingCount: Int {
        plugins.filter { benefit(for: $0) != nil }.count
    }

    var body: some View {
        Form {
            if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if plugins.isEmpty {
                Section {
                    Label(appState.isAdmin
                          ? "No plugins installed on this server."
                          : "Only server administrators can list plugins — Ultrafin still auto-detects and uses supported ones during playback.",
                          systemImage: "puzzlepiece.extension")
                        .font(Typography.body)
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
            } else {
                Section {
                    ForEach(plugins) { plugin in
                        pluginRow(plugin)
                    }
                } header: {
                    Text("\(plugins.count) installed · \(enhancingCount) enhancing Ultrafin")
                        .textCase(nil)
                }
            }

            Section {
                integrationRow(icon: "forward.frame.fill",
                               title: "Skip Intro & Credits",
                               detail: "Core media segments, with automatic fallback to the Intro Skipper plugin's endpoints.")
                integrationRow(icon: "film.stack",
                               title: "Scrubber previews",
                               detail: "Trickplay thumbnails while seeking.")
                integrationRow(icon: "iphone.gen3",
                               title: "Quick Connect",
                               detail: "Code-based sign-in from another device.")
            } header: {
                Text("Built-in integrations")
            } footer: {
                Text("Plugins install on your Jellyfin server (Dashboard → Plugins). Ultrafin detects supported ones and uses them automatically — nothing to configure here. Browse the community's catalog at the awesome-jellyfin list on GitHub.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Server Plugins")
        .tint(settings.theme.accent.color)
        .task {
            plugins = await appState.client?.installedPlugins()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } ?? []
            isLoading = false
        }
    }

    private func pluginRow(_ plugin: InstalledPlugin) -> some View {
        let benefit = benefit(for: plugin)
        return HStack(spacing: Spacing.md) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(benefit != nil ? settings.theme.accent.color : UltrafinColors.tertiaryText)
                .frame(width: iconSize + 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(subtitle(for: plugin, benefit: benefit))
                    .font(.system(size: nameSize * 0.72))
                    .foregroundStyle(benefit != nil ? settings.theme.accent.color.opacity(0.9)
                                                    : UltrafinColors.tertiaryText)
                    .lineLimit(2)
            }
            Spacer()
            if benefit != nil {
                Text("Active")
                    .font(.system(size: nameSize * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
                    .background(settings.theme.accent.color.opacity(0.9), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for plugin: InstalledPlugin, benefit: String?) -> String {
        if let benefit { return benefit }
        var parts: [String] = []
        if let version = plugin.version { parts.append("v\(version)") }
        parts.append("Server-side")
        return parts.joined(separator: " · ")
    }

    private func integrationRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(settings.theme.accent.color)
                .frame(width: iconSize + 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(detail)
                    .font(.system(size: nameSize * 0.72))
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var nameSize: CGFloat {
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
