import SwiftUI

/// Shown on launch when a saved session exists but the server can't be reached
/// (it's offline, or its address changed — e.g. a new DHCP/Macvlan IP). Offers
/// to retry or sign out so the user can point at the new address.
struct ConnectionLostView: View {
    @Environment(AppState.self) private var appState
    let session: UserSession

    @State private var retrying = false

    private var serverLabel: String {
        session.server.baseURL.host ?? session.server.baseURL.absoluteString
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(UltrafinColors.secondaryText)

            Text("Can't reach your server")
                .font(Typography.sectionTitle)
                .foregroundStyle(UltrafinColors.primaryText)

            Text("Ultrafin couldn't connect to \(serverLabel). It may be offline, or its address may have changed.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(spacing: Spacing.md) {
                PrimaryButton(title: "Retry", systemImage: "arrow.clockwise", isLoading: retrying) {
                    retry()
                }
                Button {
                    appState.signOut()
                } label: {
                    Text("Log Out & Change Server")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(UltrafinColors.primaryText)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Spacing.md, style: .continuous))
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.04, lift: false))
            }
            .frame(maxWidth: 420)
            .padding(.top, Spacing.md)
        }
        .padding(Spacing.xxl)
    }

    private func retry() {
        retrying = true
        Task {
            await appState.retryConnection()
            retrying = false
        }
    }
}
