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
    /// Present only in DEBUG demo mode (`-BLDemo YES`).
    @ObservationIgnored let demo: DemoHub?
    @ObservationIgnored let sound = SoundPlayer()

    init(makeTransport: @escaping @MainActor (String) async -> any GameTransport, demo: DemoHub? = nil) {
        self.makeTransport = makeTransport
        self.demo = demo
    }

    static func live(defaults: UserDefaults = .standard) -> AppServices {
        #if DEBUG
        if defaults.bool(forKey: LaunchOption.demo) {
            let demo = DemoHub(
                autoPlayOwnGame: defaults.bool(forKey: LaunchOption.demoAutoPlay),
                autoBuzz: defaults.string(forKey: LaunchOption.demoAutoBuzz).flatMap(DemoHub.AutoBuzz.init)
            )
            Task { await demo.startDemoHost() }
            return AppServices(makeTransport: { await demo.network.makeTransport(name: $0) }, demo: demo)
        }
        #endif
        return AppServices(makeTransport: { MultipeerTransport(displayName: $0) })
    }
}

/// DEBUG launch arguments, read from the `UserDefaults` argument domain (e.g. `-BLDemo YES`).
enum LaunchOption {
    /// Use an in-process loopback network with simulated players instead of Multipeer.
    static let demo = "BLDemo"
    /// Open straight into a flow: `host`, `join`, or `join-first` (join the first game found).
    static let route = "BLRoute"
    /// With `BLDemo`: your own hosted game also runs rounds by itself (arm, award winner, reset).
    static let demoAutoPlay = "BLDemoAutoPlay"
    /// With `BLDemo`: press your own buzzer for you: `fast` (usually win) or `early` (locked out).
    static let demoAutoBuzz = "BLDemoAutoBuzz"
}
