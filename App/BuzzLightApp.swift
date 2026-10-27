import BuzzCore
import SwiftUI

@main
struct BuzzLightApp: App {
    @State private var profile: Profile
    @State private var services = AppServices.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let profile = Profile()
        Diagnostics.start(profile: profile)
        _profile = State(initialValue: profile)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profile)
                .environment(services)
        }
        .onChange(of: scenePhase) { _, phase in
            debugLog(.app, "scene \(phase)")
        }
    }
}

/// First launch asks for a name; afterwards the app opens on Home.
struct RootView: View {
    @Environment(Profile.self) private var profile

    var body: some View {
        if profile.hasName {
            HomeView()
        } else {
            NameEntryView()
        }
    }
}
