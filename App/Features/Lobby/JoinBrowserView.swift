import BuzzCore
import SwiftUI

/// Lists games advertised nearby; tapping one joins it.
struct JoinBrowserView: View {
    let session: PlayerSession

    /// Shown after a while with no hosts: the usual causes are Local Network permission or Wi-Fi.
    @State private var showTroubleshooting = false

    var body: some View {
        List {
            if let notice = session.notice {
                Section { NoticeRow(text: notice) }
            }
            if !session.hosts.isEmpty {
                Section("Games nearby") {
                    ForEach(session.hosts) { host in
                        HostRow(host: host, isConnecting: session.phase == .connecting(host)) {
                            Task { await session.join(host) }
                        }
                        .disabled(session.phase != .browsing || !host.isCompatible)
                    }
                }
            }
        }
        .overlay {
            if session.hosts.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Looking for games…")
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .symbolEffect(.variableColor.iterative.reversing)
                    }
                } description: {
                    Text("Ask the host to tap **Host a game**. Both phones need to be on the same Wi-Fi or close together.")
                } actions: {
                    if showTroubleshooting { LocalNetworkHint() }
                }
            }
        }
        .animation(.default, value: session.hosts)
        .navigationTitle("Join a game")
        .task {
            try? await Task.sleep(for: .seconds(8))
            showTroubleshooting = true
        }
    }
}

private struct HostRow: View {
    let host: DiscoveredHost
    let isConnecting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                // Explicit colours: inside a List button, `.primary` would resolve to the tint.
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.sessionName)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if !host.isCompatible {
                        Text("Needs the same BuzzLight version — update both phones")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if isConnecting {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
        }
        .accessibilityHint(isConnecting ? "Joining" : "Joins this game")
    }
}

private struct LocalNetworkHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            Text("Still nothing? Check that **Local Network** access is on for BuzzLight, and that Wi-Fi or Bluetooth is on.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered)
        }
    }
}
