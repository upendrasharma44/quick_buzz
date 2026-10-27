import BuzzCore
import BuzzMultipeer
import BuzzNetwork
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
        // Read per game, so a DEBUG Settings change applies to the next game without relaunching.
        return AppServices(makeTransport: { name in
            let kind = TransportKind.current(defaults)
            debugLog(.app, "new game transport: \(kind.rawValue)")
            return kind.make(displayName: name)
        })
    }
}

/// Which real transport a game uses (ADR 0007). Release builds always use Network.framework;
/// DEBUG builds can switch to Multipeer for A/B device tests (Settings → Developer, or
/// `-BLTransport multipeer`). Both sides of a game must use the same transport.
enum TransportKind: String, CaseIterable, Identifiable {
    case network
    case multipeer

    static let key = "BLTransport"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .network: "Network.framework"
        case .multipeer: "Multipeer (old)"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> TransportKind {
        #if DEBUG
        return defaults.string(forKey: key).flatMap(TransportKind.init) ?? .network
        #else
        return .network
        #endif
    }

    @MainActor
    func make(displayName: String) -> any GameTransport {
        switch self {
        case .network: NetworkTransport(displayName: displayName)
        case .multipeer: MultipeerTransport(displayName: displayName)
        }
    }
}

/// DEBUG launch arguments, read from the `UserDefaults` argument domain (e.g. `-BLDemo YES`).
enum LaunchOption {
    /// Use an in-process loopback network with simulated players instead of a real transport.
    static let demo = "BLDemo"
    /// Open straight into a flow: `host`, `join`, `join-first` (join the first game found), or `settings`.
    static let route = "BLRoute"
    /// With `BLDemo`: your own hosted game also runs rounds by itself (arm, award winner, reset).
    static let demoAutoPlay = "BLDemoAutoPlay"
    /// With `BLDemo`: press your own buzzer for you: `fast` (usually win) or `early` (locked out).
    static let demoAutoBuzz = "BLDemoAutoBuzz"
}
