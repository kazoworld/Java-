import SwiftUI

/// A dashboard-lite for server admins: server details, a library scan trigger,
/// live "streaming now" sessions, and the recent-activity feed — the everyday
/// slice of the Jellyfin web dashboard, from the couch.
struct ServerDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var info: ServerSystemInfo?
    @State private var sessions: [ActiveSession] = []
    @State private var activity: [ActivityEntry] = []
    @State private var isLoading = true
    @State private var isScanning = false
    @State private var toast: String?

    var body: some View {
        Form {
            serverSection
            librarySection
            sessionsSection
            activitySection
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Server")
        .tint(settings.theme.accent.color)
        .toast($toast)
        .task {
            await loadOnce()
            // Keep "Streaming Now" live while the screen is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let client = appState.client else { continue }
                sessions = await client.activeSessions()
            }
        }
    }

    private func loadOnce() async {
        guard let client = appState.client else { isLoading = false; return }
        async let infoTask = client.systemInfo()
        async let sessionsTask = client.activeSessions()
        async let activityTask = client.recentActivity(limit: 12)
        info = await infoTask
        sessions = await sessionsTask
        activity = await activityTask
        isLoading = false
    }

    // MARK: - Server

    @ViewBuilder
    private var serverSection: some View {
        Section {
            if isLoading && info == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                LabeledContent("Name", value: info?.serverName ?? appState.client.map { _ in "—" } ?? "—")
                LabeledContent("Jellyfin", value: info?.version ?? "—")
                if let os = info?.operatingSystem, !os.isEmpty {
                    LabeledContent("System", value: os)
                }
                if info?.hasPendingRestart == true {
                    Label("The server has a pending restart", systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Server")
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section {
            Button {
                guard !isScanning else { return }
                isScanning = true
                Task {
                    let ok = await appState.client?.refreshAllLibraries() ?? false
                    toast = ok ? "Library scan started" : "Couldn't start the scan"
                    Haptics.play(ok ? .success : .warning)
                    // Brief cooldown so the button can't be hammered.
                    try? await Task.sleep(for: .seconds(3))
                    isScanning = false
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    if isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(settings.theme.accent.color)
                    }
                    Text(isScanning ? "Scan requested…" : "Scan All Libraries")
                        .foregroundStyle(UltrafinColors.primaryText)
                }
            }
            .disabled(isScanning)
        } header: {
            Text("Library")
        } footer: {
            Text("Scans every library for new and changed media — same as the dashboard's Scan All Libraries.")
        }
    }

    // MARK: - Streaming now

    @ViewBuilder
    private var sessionsSection: some View {
        let streaming = sessions.filter { $0.nowPlayingItem != nil }
        Section {
            if streaming.isEmpty {
                Text("Nothing streaming right now.")
                    .font(Typography.body)
                    .foregroundStyle(UltrafinColors.secondaryText)
            } else {
                ForEach(streaming) { session in
                    sessionRow(session)
                }
            }
        } header: {
            Text("Streaming Now")
        } footer: {
            Text("Live view of active playback across all devices — refreshes every few seconds.")
        }
    }

    private func sessionRow(_ session: ActiveSession) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: session.playState?.isPaused == true ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: rowIconSize))
                .foregroundStyle(session.playState?.isPaused == true
                                 ? UltrafinColors.tertiaryText : settings.theme.accent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlayingTitle(session))
                    .font(.system(size: rowTextSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                Text(sessionMeta(session))
                    .font(.system(size: rowTextSize * 0.75))
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if let percent = progressPercent(session) {
                Text(percent)
                    .font(.system(size: rowTextSize * 0.8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(UltrafinColors.tertiaryText)
            }
        }
        .padding(.vertical, 2)
    }

    private func nowPlayingTitle(_ session: ActiveSession) -> String {
        guard let item = session.nowPlayingItem else { return "—" }
        if let series = item.seriesName, let name = item.name { return "\(series) · \(name)" }
        return item.name ?? "—"
    }

    private func sessionMeta(_ session: ActiveSession) -> String {
        [session.userName, session.deviceName ?? session.client]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func progressPercent(_ session: ActiveSession) -> String? {
        guard let position = session.playState?.positionTicks,
              let total = session.nowPlayingItem?.runTimeTicks, total > 0 else { return nil }
        return "\(Int((Double(position) / Double(total) * 100).rounded()))%"
    }

    // MARK: - Activity

    @ViewBuilder
    private var activitySection: some View {
        Section {
            if activity.isEmpty {
                Text(isLoading ? "Loading…" : "No recent activity.")
                    .font(Typography.body)
                    .foregroundStyle(UltrafinColors.secondaryText)
            } else {
                ForEach(activity) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: rowTextSize, weight: .medium, design: .rounded))
                            .foregroundStyle(UltrafinColors.primaryText)
                            .lineLimit(2)
                        Text(relativeDate(entry.date))
                            .font(.system(size: rowTextSize * 0.75))
                            .foregroundStyle(UltrafinColors.tertiaryText)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Recent Activity")
        }
    }

    /// "3 minutes ago" from the server's ISO-8601 timestamp.
    private func relativeDate(_ iso: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: iso) ?? plain.date(from: iso) else {
            return String(iso.prefix(16)).replacingOccurrences(of: "T", with: "  ")
        }
        return date.formatted(.relative(presentation: .named))
    }

    // MARK: - Metrics

    private var rowTextSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var rowIconSize: CGFloat {
        #if os(tvOS)
        30
        #else
        22
        #endif
    }
}
