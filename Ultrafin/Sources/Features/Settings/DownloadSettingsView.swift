import SwiftUI

/// Offline download preferences. The download engine itself is an upcoming
/// feature — these choices persist so they're ready when it lands.
struct DownloadSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Download quality", selection: $settings.downloads.quality) {
                    ForEach(DownloadPreferences.Quality.allCases) { Text($0.label).tag($0) }
                }
                Picker("Max storage", selection: $settings.downloads.maxStorageGB) {
                    ForEach([5, 10, 25, 50, 100], id: \.self) { Text("\($0) GB").tag($0) }
                }
                Toggle("Allow cellular downloads", isOn: $settings.downloads.allowCellular)
            } header: {
                Text("Downloads")
            }

            Section {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(UltrafinColors.tertiaryText)
                    Text("No downloads yet")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text("Saving titles for offline playback is coming soon. Your preferences above are saved for when it arrives.")
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            } header: {
                Text("My Downloads")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Downloads")
        .tint(settings.accent)
    }
}
