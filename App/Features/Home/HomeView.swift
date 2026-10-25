import SwiftUI

/// Landing screen: host or join a game.
struct HomeView: View {
    enum Route: Hashable {
        case host
        case join(autoJoinFirst: Bool = false)
    }

    @Environment(Profile.self) private var profile
    @State private var path: [Route] = Self.launchRoute()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.tint)
                Text("QuickBuzz")
                    .font(.largeTitle.bold())
                Text("Who buzzed first?")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { path.append(.host) } label: {
                    Label("Host a game", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { path.append(.join()) } label: {
                    Label("Join a game", systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Text("Playing as \(Text(profile.name).bold())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .host:
                    HostFlowView(onExit: goHome)
                case .join(let autoJoinFirst):
                    JoinFlowView(autoJoinFirst: autoJoinFirst, onExit: goHome)
                }
            }
        }
    }

    private func goHome() { path.removeAll() }

    /// DEBUG: `-QBRoute host|join|join-first` opens straight into a flow (for demos/screenshots).
    private static func launchRoute() -> [Route] {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: LaunchOption.route) {
        case "host": return [.host]
        case "join": return [.join()]
        case "join-first": return [.join(autoJoinFirst: true)]
        default: return []
        }
        #else
        return []
        #endif
    }
}

#Preview {
    HomeView()
        .environment(Profile(defaults: UserDefaults(suiteName: "preview")!))
        .environment(AppServices.live())
}
