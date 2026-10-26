import Foundation
import Testing
@testable import BuzzCore

/// Liveness on both ends (heartbeat pings, silence timeouts) and the buzz re-send — the fixes for
/// peer-to-peer Wi-Fi links that stall: idle TCP keepalive killed them on one side only, and a
/// buzz pressed into the dead link was lost.
@MainActor
@Suite("Heartbeat and liveness")
struct HeartbeatTests {
    let network = LoopbackNetwork()

    func fastHost() async -> HostSession {
        HostSession(hostID: PlayerID(rawValue: "host"), hostName: "Hana",
                    transport: await network.makeTransport(name: "Hana"), flushDelay: .zero,
                    heartbeatInterval: .milliseconds(20), silenceTimeout: .milliseconds(200))
    }

    @Test func hostDropsAPlayerThatStopsAnswering() async throws {
        let host = await fastHost()
        await host.start()
        // A "player" that says hello and then never answers a ping (its link silently died).
        let mute = await network.makeTransport(name: "Mute")
        try await mute.connect(to: host.localPeer)
        try await mute.send(.hello(playerID: PlayerID(rawValue: "mute"), name: "Mute"), to: [host.localPeer])
        #expect(await eventually { host.engine.players.map(\.name) == ["Hana", "Mute"] })
        #expect(await eventually(timeout: .seconds(2)) { host.engine.players.map(\.name) == ["Hana"] },
                "dropped after the silence timeout")
        await host.end()
    }

    @Test func hostKeepsAPlayerThatAnswers() async throws {
        let host = await fastHost()
        await host.start()
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat"), name: "Pat",
                                transport: await network.makeTransport(name: "Pat"))
        await pat.start()
        #expect(await eventually { !pat.hosts.isEmpty })
        await pat.join(try #require(pat.hosts.first))
        #expect(await eventually { host.engine.players.count == 2 })
        try await Task.sleep(for: .milliseconds(600))  // 3× the silence timeout
        #expect(host.engine.players.map(\.name) == ["Hana", "Pat"], "pongs keep the player in")
        #expect(pat.phase == .joined(try #require(pat.host)))
        await host.end()
    }

    @Test func playerDropsAHostThatGoesSilent() async {
        let transport = ScriptedTransport()  // a host that never pings
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat"), name: "Pat", transport: transport,
                                reconnectTimeout: .seconds(5), hostSilenceTimeout: .milliseconds(100))
        let host = DiscoveredHost(id: PeerID(rawValue: "host"), sessionName: "Hana's game")
        await pat.start()
        await pat.join(host)
        #expect(await eventually { pat.phase == .joined(host) })
        #expect(await eventually(timeout: .seconds(2)) { transport.disconnectCalls == [host.id] })
        // The drop goes through the normal path: reconnecting, then rejoined (the double accepts).
        #expect(await eventually { transport.connectCalls.count >= 2 })
    }

    @Test func playerKeepsAHostThatPings() async throws {
        let host = await fastHost()
        await host.start()
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat"), name: "Pat",
                                transport: await network.makeTransport(name: "Pat"),
                                hostSilenceTimeout: .milliseconds(150))
        await pat.start()
        #expect(await eventually { !pat.hosts.isEmpty })
        let target = try #require(pat.hosts.first)
        await pat.join(target)
        #expect(await eventually { pat.phase == .joined(target) })
        try await Task.sleep(for: .milliseconds(500))
        #expect(pat.phase == .joined(target), "pings keep the host alive for the player")
        await host.end()
    }

    @Test func buzzLostWithTheLinkIsResentAfterReconnecting() async {
        let transport = ScriptedTransport()
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat"), name: "Pat", transport: transport,
                                retryDelay: .milliseconds(10))
        let hostPeer = PeerID(rawValue: "host")
        let host = DiscoveredHost(id: hostPeer, sessionName: "Hana's game")
        let players = [Player(id: PlayerID(rawValue: "h"), name: "Hana", isHost: true)]
        await pat.start()
        await pat.join(host)
        transport.emit(.message(.welcome(snapshot: SessionSnapshot(players: players, round: RoundState(id: RoundID(1)))),
                                from: hostPeer, receivedAt: .now))
        transport.emit(.message(.armed(round: RoundID(1)), from: hostPeer, receivedAt: .now))
        #expect(await eventually { pat.engine.status == .ready })
        pat.buzz()
        #expect(await eventually { transport.sent.contains(.init(message: .buzz(round: RoundID(1)), to: [hostPeer])) })

        // The link dies before the host saw it; the player reconnects (the double accepts at once)
        // and the host's snapshot shows round 1 still open without Pat.
        transport.emit(.peerDisconnected(hostPeer))
        #expect(await eventually { transport.sent.filter { $0.message == .hello(playerID: PlayerID(rawValue: "pat"), name: "Pat") }.count == 2 })
        transport.emit(.message(.welcome(snapshot: SessionSnapshot(players: players, round: RoundState(id: RoundID(1), phase: .armed))),
                                from: hostPeer, receivedAt: .now))
        #expect(await eventually { transport.sent.filter { $0.message == .buzz(round: RoundID(1)) }.count == 2 },
                "the buzz is delivered again")
        #expect(pat.engine.status == .buzzed)
    }
}
