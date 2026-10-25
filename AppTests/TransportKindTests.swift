import BuzzCore
import BuzzMultipeer
import BuzzNetwork
import Foundation
import Testing
@testable import BuzzLight

@MainActor
@Suite("Transport choice")
struct TransportKindTests {
    let defaults: UserDefaults = {
        let suite = "TransportKindTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }()

    @Test func networkFrameworkIsTheDefault() {
        #expect(TransportKind.current(defaults) == .network)
    }

    @Test func debugBuildsCanSwitchToMultipeer() {
        defaults.set("multipeer", forKey: TransportKind.key)
        #if DEBUG
        #expect(TransportKind.current(defaults) == .multipeer)
        #else
        #expect(TransportKind.current(defaults) == .network, "release builds ignore the switch")
        #endif
    }

    @Test func unknownValuesFallBackToNetwork() {
        defaults.set("carrier-pigeon", forKey: TransportKind.key)
        #expect(TransportKind.current(defaults) == .network)
    }

    @Test func eachKindMakesItsTransport() async {
        let network = TransportKind.network.make(displayName: "A")
        let multipeer = TransportKind.multipeer.make(displayName: "B")
        #expect(network is NetworkTransport)
        #expect(multipeer is MultipeerTransport)
        await network.stop()
        await multipeer.stop()
    }
}
