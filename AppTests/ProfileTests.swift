import BuzzCore
import Foundation
import Testing
@testable import QuickBuzz

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
    /// The simulated players the simulator demo relies on actually join a user-hosted game.
    @Test func botsJoinTheUsersGame() async throws {
        let demo = DemoHub()
        let host = HostSession(hostID: PlayerID(), hostName: "Me",
                               transport: await demo.network.makeTransport(name: "Me"), flushDelay: .zero)
        await host.start()
        demo.hostStarted(host)
        let deadline = ContinuousClock.now + .seconds(5)
        while host.engine.players.count < 4, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(host.engine.players.map(\.name) == ["Me", "Cleo", "Dev", "Eli"])
        await host.end()
    }

    @Test func demoHostIsJoinable() async throws {
        let demo = DemoHub()
        await demo.startDemoHost()
        let me = PlayerSession(playerID: PlayerID(), name: "Me", transport: await demo.network.makeTransport(name: "Me"))
        await me.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while me.hosts.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let host = try #require(me.hosts.first)
        #expect(host.sessionName == "Quiz Night (demo)")
        await me.join(host)
        while me.engine.players.count < 4, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(me.engine.players.map(\.name) == ["Quiz Master", "Ava", "Ben", "Me"])
        await me.leave()
    }
}
