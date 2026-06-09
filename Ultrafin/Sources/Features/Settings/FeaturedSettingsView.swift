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
                Picker("Content type", selection: $settings.featured.contentType) {
                    ForEach(FeaturedPreferences.ContentType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Source", selection: $settings.featured.source) {
                    ForEach(FeaturedPreferences.Source.allCases) { Text($0.label).tag($0) }
                }
                Picker("Item count", selection: $settings.featured.itemCount) {
                    ForEach([3, 5, 8, 10], id: \.self) { Text("\($0)").tag($0) }
                }
            } header: {
                Text("Content")
            }
            .disabled(!settings.isFeaturedEnabled)

            Section {
                NavigationLink {
                    FeaturedLibraryPickerView()
                } label: {
                    LabeledContent("Libraries", value: librarySummary)
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Limit the media bar to specific libraries, or include them all.")
            }
            .disabled(!settings.isFeaturedEnabled)

            Section {
                Toggle("Auto advance", isOn: $settings.featured.autoAdvance)
                Picker("Interval", selection: $settings.featured.rotationSeconds) {
                    ForEach([5, 8, 12, 20], id: \.self) { Text("\($0)s").tag($0) }
                }
                .disabled(!settings.featured.autoAdvance)
            } header: {
                Text("Behavior")
            } footer: {
                Text("Automatically rotate through featured items.")
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

    private var librarySummary: String {
        let ids = settings.featured.sourceLibraryIDs
        return ids.isEmpty ? "All Libraries" : "\(ids.count) selected"
    }
}
