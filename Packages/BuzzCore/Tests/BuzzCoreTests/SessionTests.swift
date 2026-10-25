import Foundation
import Testing
@testable import BuzzCore

/// `HostSession` + `PlayerSession` wired through `LoopbackNetwork`: the full lobby lifecycle
/// the app drives, minus the radio.
@MainActor
@Suite("Sessions over loopback")
struct SessionTests {
    let network = LoopbackNetwork()

    func makeHost(name: String = "Hana") async -> HostSession {
        HostSession(
            hostID: PlayerID(rawValue: "host-\(name)"),
            hostName: name,
            transport: await network.makeTransport(name: name),
            flushDelay: .zero
        )
    }

    func makePlayer(
        _ name: String,
        id: String? = nil,
        connectTimeout: Duration = .seconds(5),
        reconnectTimeout: Duration = .seconds(5)
    ) async -> PlayerSession {
        PlayerSession(
            playerID: PlayerID(rawValue: id ?? "id-\(name)"),
            name: name,
            transport: await network.makeTransport(name: name),
            connectTimeout: connectTimeout,
            reconnectTimeout: reconnectTimeout,
            retryDelay: .milliseconds(10)
        )
    }

    /// Host started, player browsing and joined.
    func joined(_ player: PlayerSession, to host: HostSession) async throws {
        await player.start()
        #expect(await eventually { player.hosts.contains { $0.id == host.localPeer } })
        let found = try #require(player.hosts.first { $0.id == host.localPeer })
        await player.join(found)
        #expect(await eventually { player.engine.status == .waiting })
    }

    // MARK: - Discovery

    @Test func defaultSessionNameUsesHostName() async {
        let host = await makeHost(name: "Hana")
        #expect(host.sessionName == "Hana's game")
    }

    @Test func playerSeesHostsSortedAndLosesThemWhenTheyEnd() async {
        let zed = await makeHost(name: "Zed")
        let amy = await makeHost(name: "Amy")
        await zed.start()
        await amy.start()

        let player = await makePlayer("Pat")
        await player.start()
        #expect(player.phase == .browsing)
        #expect(await eventually { player.hosts.map(\.sessionName) == ["Amy's game", "Zed's game"] })

        await zed.end()
        #expect(await eventually { player.hosts.map(\.sessionName) == ["Amy's game"] })
    }

    @Test func hostStartedAfterPlayerIsStillFound() async {
        let player = await makePlayer("Pat")
        await player.start()
        let host = await makeHost()
        await host.start()
        #expect(await eventually { player.hosts.count == 1 })
    }

    // MARK: - Joining

    @Test func joiningSyncsRosterOnBothSides() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        let sam = await makePlayer("Sam")
        try await joined(pat, to: host)
        try await joined(sam, to: host)

        #expect(host.engine.players.map(\.name) == ["Hana", "Pat", "Sam"])
        #expect(await eventually { pat.engine.players.map(\.name) == ["Hana", "Pat", "Sam"] })
        #expect(pat.engine.host?.name == "Hana")
        guard case .joined(let joinedHost) = pat.phase else { Issue.record("not joined"); return }
        #expect(joinedHost.id == host.localPeer)
    }

    @Test func twoPlayersWithTheSameNameAreDistinct() async throws {
        let host = await makeHost()
        await host.start()
        try await joined(await makePlayer("Sam", id: "sam-1"), to: host)
        try await joined(await makePlayer("Sam", id: "sam-2"), to: host)
        #expect(host.engine.players.map(\.name) == ["Hana", "Sam", "Sam"])
        #expect(Set(host.engine.players.map(\.id)).count == 3)
    }

    @Test func joiningAVanishedHostFailsBackToBrowsing() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        await pat.start()
        #expect(await eventually { pat.hosts.count == 1 })
        let stale = try #require(pat.hosts.first)
        await host.end()

        await pat.join(stale)
        #expect(pat.phase == .browsing)
        #expect(pat.notice?.contains("Couldn't join Hana's game") == true)
    }

    @Test func joinTimesOutWhenTheHostNeverAnswers() async throws {
        // A transport that accepts the invitation request but never connects.
        let silent = ScriptedTransport(autoConnect: false)
        let pat = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: silent,
                                connectTimeout: .milliseconds(50))
        await pat.start()
        let host = DiscoveredHost(id: PeerID(rawValue: "h"), sessionName: "Ghost")
        await pat.join(host)
        #expect(pat.phase == .connecting(host))
        #expect(await eventually { pat.phase == .browsing })
        #expect(pat.notice != nil)
    }

    // MARK: - Leaving and ending

    @Test func playerLeavingUpdatesHostRoster() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        try await joined(pat, to: host)

        await pat.leave()
        #expect(pat.phase == .ended(.left))
        #expect(await eventually { host.engine.players.map(\.name) == ["Hana"] })
    }

    @Test func kickedPlayerEndsWithReasonKicked() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        let sam = await makePlayer("Sam")
        try await joined(pat, to: host)
        try await joined(sam, to: host)

        await host.kick(PlayerID(rawValue: "id-Pat"))
        #expect(await eventually { pat.phase == .ended(.kicked) })
        #expect(await eventually { sam.engine.players.map(\.name) == ["Hana", "Sam"] })
        #expect(sam.phase == .joined(DiscoveredHost(id: host.localPeer, sessionName: "Hana's game")))
    }

    @Test func hostEndingSendsEveryoneHome() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        try await joined(pat, to: host)

        await host.end()
        #expect(host.phase == .ended)
        #expect(await eventually { pat.phase == .ended(.hostEnded) })
        await host.end()  // idempotent
    }

    @Test func hostVanishingWithoutEndTimesOutAsConnectionLost() async throws {
        let hostTransport = await network.makeTransport(name: "Hana")
        let host = HostSession(hostID: PlayerID(rawValue: "h"), hostName: "Hana", transport: hostTransport)
        await host.start()
        let pat = await makePlayer("Pat", reconnectTimeout: .milliseconds(100))
        try await joined(pat, to: host)

        // Simulate a crash: the host's transport disappears without sending `end`.
        await hostTransport.stop()
        #expect(await eventually { pat.phase == .reconnecting(DiscoveredHost(id: host.localPeer, sessionName: "Hana's game")) })
        #expect(await eventually { pat.phase == .ended(.connectionLost) })
        #expect(pat.engine.status == .ended)
        #expect(pat.hosts.isEmpty)
    }

    // MARK: - Reconnection

    @Test func droppedPlayerReconnectsAndKeepsIdentity() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        try await joined(pat, to: host)
        _ = host.engine.award(points: 2, to: PlayerID(rawValue: "id-Pat"))

        await network.dropLink(between: host.localPeer, and: pat.localPeer)
        // Host forgets the player while disconnected, player retries and comes back.
        #expect(await eventually { pat.phase == .joined(DiscoveredHost(id: host.localPeer, sessionName: "Hana's game")) })
        #expect(await eventually { host.engine.players.map(\.name) == ["Hana", "Pat"] })
        #expect(await eventually { pat.engine.status == .waiting })
        #expect(host.engine.scores[PlayerID(rawValue: "id-Pat")] == 2, "scores survive a reconnect")
    }

    @Test func messagesFromOtherPeersAreIgnoredByPlayer() async throws {
        let host = await makeHost()
        await host.start()
        let pat = await makePlayer("Pat")
        try await joined(pat, to: host)
        // A second host on the same network cannot drive Pat's screen.
        let rogue = await makeHost(name: "Rogue")
        await rogue.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(pat.engine.players.map(\.name) == ["Hana", "Pat"])
        #expect(pat.phase == .joined(DiscoveredHost(id: host.localPeer, sessionName: "Hana's game")))
    }
}
