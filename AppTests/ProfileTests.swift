import BuzzCore
import Foundation
import Testing
@testable import BuzzLight

@MainActor
@Suite("Profile")
struct ProfileTests {
    /// Fresh, isolated defaults per test.
    let defaults: UserDefaults = {
        let suite = "ProfileTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }()

    @Test func firstLaunchHasNoNameButAStableID() {
        let profile = Profile(defaults: defaults)
        #expect(!profile.hasName)
        #expect(!profile.playerID.rawValue.isEmpty)
        #expect(Profile(defaults: defaults).playerID == profile.playerID, "ID persists across launches")
    }

    @Test func nameIsNormalizedAndPersisted() {
        let profile = Profile(defaults: defaults)
        #expect(profile.setName("  Upendra   Sharma \n"))
        #expect(profile.name == "Upendra Sharma")
        #expect(Profile(defaults: defaults).name == "Upendra Sharma")
    }

    @Test func blankNamesAreRejected() {
        let profile = Profile(defaults: defaults)
        #expect(!profile.setName("   "))
        #expect(!profile.setName(""))
        #expect(!profile.hasName)
    }

    @Test func longNamesAreCapped() {
        let profile = Profile(defaults: defaults)
        profile.setName(String(repeating: "x", count: 100))
        #expect(profile.name.count == Profile.maxNameLength)
    }

    @Test func normalizedRules() {
        #expect(Profile.normalized("a\tb") == "a b")
        #expect(Profile.normalized(" ") == nil)
        #expect(Profile.normalized("Zoë 🐝") == "Zoë 🐝")
    }
}

@MainActor
@Suite("Demo mode")
struct DemoModeTests {
    /// Fast, deterministic-enough timings so the demo's behaviour can be checked in milliseconds.
    static let fast = DemoHub.Timing(
        joinInterval: .milliseconds(20), reaction: 10...40, earlyPressChance: 0,
        idleBeforeArm: .milliseconds(60), showResults: .milliseconds(80),
        abandonRound: .seconds(2), poll: .milliseconds(10)
    )

    func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }

    func hostedGame(_ demo: DemoHub) async -> HostSession {
        let host = HostSession(hostID: PlayerID(), hostName: "Me",
                               transport: await demo.network.makeTransport(name: "Me"), flushDelay: .zero)
        await host.start()
        demo.hostStarted(host)
        return host
    }

    /// The simulated players the simulator demo relies on actually join a user-hosted game.
    @Test func botsJoinTheUsersGame() async throws {
        let demo = DemoHub(timing: Self.fast)
        let host = await hostedGame(demo)
        try await waitUntil { host.engine.players.count == 4 }
        #expect(host.engine.players.map(\.name) == ["Me", "Cleo", "Dev", "Eli"])
        await host.end()
    }

    @Test func botsBuzzOnceTheBuzzersOpen() async throws {
        let demo = DemoHub(timing: Self.fast)
        let host = await hostedGame(demo)
        try await waitUntil { host.engine.players.count == 4 }
        try await Task.sleep(for: .milliseconds(50))  // let the bots see the idle round
        #expect(host.engine.round.ranking.isEmpty, "no early presses with earlyPressChance 0")
        await host.arm()
        try await waitUntil { host.engine.round.ranking.count == 3 }
        #expect(Set(host.engine.round.ranking.map { host.engine.name(of: $0.playerID) }) == ["Cleo", "Dev", "Eli"])
        await host.end()
    }

    @Test func ownGameAutoPlaysWhenAsked() async throws {
        let demo = DemoHub(timing: Self.fast, autoPlayOwnGame: true)
        let host = await hostedGame(demo)
        try await waitUntil { host.engine.round.id.rawValue >= 3 }
        #expect(host.engine.round.id.rawValue >= 3, "rounds advance by themselves")
        #expect(host.engine.scores.values.reduce(0, +) >= 2, "each round's winner got a point")
        await host.end()
    }

    @Test func demoHostIsJoinableAndPlaysWithARealPlayer() async throws {
        let demo = DemoHub(timing: Self.fast)
        await demo.startDemoHost()
        let me = PlayerSession(playerID: PlayerID(), name: "Me", transport: await demo.network.makeTransport(name: "Me"))
        await me.start()
        try await waitUntil { !me.hosts.isEmpty }
        let host = try #require(me.hosts.first)
        #expect(host.sessionName == "Quiz Night (demo)")
        await me.join(host)
        try await waitUntil { me.engine.players.count == 4 }
        #expect(me.engine.players.map(\.name) == ["Quiz Master", "Ava", "Ben", "Me"])

        // With a real player present the demo host runs rounds: the player sees them arrive.
        try await waitUntil { (me.engine.round?.id.rawValue ?? 0) >= 3 }
        #expect((me.engine.round?.id.rawValue ?? 0) >= 3)
        #expect(!me.engine.scores.isEmpty)
        await me.leave()
        await demo.stop()
    }
}
