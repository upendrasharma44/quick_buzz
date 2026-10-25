import SwiftUI

@main
struct QuickBuzzApp: App {
    @State private var profile = Profile()
    @State private var services = AppServices.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profile)
                .environment(services)
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
