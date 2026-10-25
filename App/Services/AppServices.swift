import BuzzCore
import BuzzMultipeer
import Foundation
import Observation

/// App-wide dependencies, injected through the SwiftUI environment.
@MainActor
@Observable
final class AppServices {
    /// Creates a fresh transport for one game session (hosting or joining).
    @ObservationIgnored let makeTransport: @MainActor (_ displayName: String) async -> any GameTransport
    /// Present only in DEBUG demo mode (`-QBDemo YES`).
    @ObservationIgnored let demo: DemoHub?

    init(makeTransport: @escaping @MainActor (String) async -> any GameTransport, demo: DemoHub? = nil) {
        self.makeTransport = makeTransport
        self.demo = demo
    }

    static func live(defaults: UserDefaults = .standard) -> AppServices {
        #if DEBUG
        if defaults.bool(forKey: LaunchOption.demo) {
            let demo = DemoHub()
            Task { await demo.startDemoHost() }
            return AppServices(makeTransport: { await demo.network.makeTransport(name: $0) }, demo: demo)
        }
        #endif
        return AppServices(makeTransport: { MultipeerTransport(displayName: $0) })
    }
}

/// DEBUG launch arguments, read from the `UserDefaults` argument domain (e.g. `-QBDemo YES`).
enum LaunchOption {
    /// Use an in-process loopback network with simulated players instead of Multipeer.
    static let demo = "QBDemo"
    /// Open straight into a flow: `host`, `join`, or `join-first` (join the first game found).
    static let route = "QBRoute"
}
