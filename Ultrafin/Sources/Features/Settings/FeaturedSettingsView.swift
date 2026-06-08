import SwiftUI

/// The dedicated "Media Bar" page — controls the big rotating hero on Home.
struct FeaturedSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Show media bar", isOn: Binding(
                    get: { settings.isFeaturedEnabled },
                    set: { settings.isFeaturedEnabled = $0 }
                ))
            } footer: {
                Text("The featured banner at the top of Home. You can also reorder it in Home Layout.")
            }

            Section {
                Picker("Content", selection: $settings.featured.source) {
                    ForEach(FeaturedPreferences.Source.allCases) { Text($0.label).tag($0) }
                }
                Picker("Rotate every", selection: $settings.featured.rotationSeconds) {
                    ForEach([5, 8, 12, 20], id: \.self) { Text("\($0)s").tag($0) }
                }
                Picker("Number of items", selection: $settings.featured.maxItems) {
                    ForEach([3, 5, 8, 10], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            .disabled(!settings.isFeaturedEnabled)
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Media Bar")
        .tint(settings.theme.accent.color)
    }
}
