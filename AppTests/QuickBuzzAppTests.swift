import BuzzCore
import Testing
@testable import QuickBuzz

/// Smoke test: the app target links against the packages and can host a game.
@MainActor
@Suite("App")
struct QuickBuzzAppTests {
    @Test func appCanCreateHostEngine() {
        let engine = HostEngine(hostID: PlayerID(), hostName: "Me")
        #expect(engine.players.count == 1)
        #expect(engine.arm().count == 1)
    }
}
