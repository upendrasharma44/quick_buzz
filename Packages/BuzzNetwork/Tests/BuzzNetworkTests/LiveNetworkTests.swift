import BuzzCore
import Foundation
import Testing
@testable import BuzzNetwork

/// Real Network.framework (Bonjour, TLS-PSK, WebSocket, peer-to-peer Wi-Fi allowed) between
/// transports in this process. Opt-in because it needs the local network:
///
///     BUZZLIGHT_LIVE_NETWORK=1 swift test --package-path Packages/BuzzNetwork
@Suite(
    "Live Network.framework (opt-in)",
    .enabled(if: ProcessInfo.processInfo.environment["BUZZLIGHT_LIVE_NETWORK"] != nil),
    .serialized
)
struct LiveNetworkTests {
    func uniqueSessionName(_ label: String) -> String { "\(label) \(UUID().uuidString.prefix(6))" }

    /// Host advertising, player that has found it.
    func hostAndFoundGame(_ label: String) async throws -> (NetworkTransport, EventLog, NetworkTransport, EventLog, DiscoveredHost) {
        let host = NetworkTransport(displayName: "Host")
        let player = NetworkTransport(displayName: "Player")
        let hostLog = EventLog(host.events)
        let playerLog = EventLog(player.events)
        let name = uniqueSessionName(label)
        try await host.startHosting(sessionName: name)
        try await player.startBrowsing()
        let found = try await playerLog.first(within: .seconds(20)) { event -> DiscoveredHost? in
            if case .hostFound(let h) = event, h.sessionName == name { h } else { nil }
        }
        return (host, hostLog, player, playerLog, found)
    }

    @Test(.timeLimit(.minutes(1)))
    func discoverConnectExchangeAndDisconnect() async throws {
        let (host, hostLog, player, playerLog, found) = try await hostAndFoundGame("Handshake")
        #expect(found.isCompatible)
        try await player.connect(to: found.id)
        let playerOnHost = try await hostLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }
        await player.stopBrowsing()

        let me = PlayerID(rawValue: "live")
        try await player.send(.hello(playerID: me, name: "Player"), to: [found.id])
        let hello = try await hostLog.first(within: .seconds(10)) { event -> GameMessage? in
            if case .message(let m, let from, _) = event, from == playerOnHost { m } else { nil }
        }
        #expect(hello == .hello(playerID: me, name: "Player"))

        try await host.send(.armed(round: RoundID(1)), to: [playerOnHost])
        let armed = try await playerLog.first(within: .seconds(10)) { event -> GameMessage? in
            if case .message(let m, _, _) = event { m } else { nil }
        }
        #expect(armed == .armed(round: RoundID(1)))

        // The host closing must be noticed at once, not when TCP keepalive gives up (~7 s).
        await host.stop()
        _ = try await playerLog.first(within: .seconds(3)) { event -> PeerID? in
            if case .peerDisconnected(let p) = event, p == found.id { p } else { nil }
        }
        await player.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func connectRightAfterABrowserRestart() async throws {
        let (host, hostLog, player, playerLog, found) = try await hostAndFoundGame("Restart")
        await player.stopBrowsing()
        try await player.startBrowsing()
        try await player.connect(to: found.id)  // before the new browser has re-found the host
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }
        _ = try await hostLog.first(within: .seconds(5)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        await host.stop(); await player.stop()
    }

    @Test(.timeLimit(.minutes(2)))
    func hostTurnsAwayThePlayerOverTheLimit() async throws {
        let host = NetworkTransport(displayName: "Host")
        let hostLog = EventLog(host.events)
        let name = uniqueSessionName("Full")
        try await host.startHosting(sessionName: name)

        var players: [(NetworkTransport, EventLog, PeerID)] = []
        for i in 0...NetworkTransport.maxPlayers {  // one more than allowed
            let player = NetworkTransport(displayName: "P\(i)")
            let log = EventLog(player.events)
            try await player.startBrowsing()
            let found = try await log.first(within: .seconds(20)) { event -> DiscoveredHost? in
                if case .hostFound(let h) = event, h.sessionName == name { h } else { nil }
            }
            players.append((player, log, found.id))
        }
        for (index, (player, log, hostID)) in players.enumerated() where index < NetworkTransport.maxPlayers {
            try await player.connect(to: hostID)
            _ = try await log.first(within: .seconds(20)) { event -> PeerID? in
                if case .peerConnected(let p) = event, p == hostID { p } else { nil }
            }
        }
        #expect(hostLog.count { if case .peerConnected = $0 { true } else { false } } == NetworkTransport.maxPlayers)

        let (extra, extraLog, hostID) = players[NetworkTransport.maxPlayers]
        // Known limitation: the refusal only arrives via the 18 s connection expiry (the client
        // keeps preparing on another path). Stage 4: advertise the player count so full games
        // show as full in the Join list.
        try await extra.connect(to: hostID)
        let outcome = try await extraLog.first(within: .seconds(25)) { event -> String? in
            switch event {
            case .peerConnected(let p) where p == hostID: "connected"
            case .failed(.connectionFailed(let p)) where p == hostID: "refused"
            default: nil
            }
        }
        #expect(outcome == "refused")
        #expect(hostLog.count { if case .peerConnected = $0 { true } else { false } } == NetworkTransport.maxPlayers)
        await host.stop()
        for (player, _, _) in players { await player.stop() }
    }

    @Test(.timeLimit(.minutes(1)))
    func frameFromAnotherProtocolVersionGetsThePlayerTurnedAway() async throws {
        let (host, hostLog, player, playerLog, found) = try await hostAndFoundGame("Version")
        try await player.connect(to: found.id)
        let playerOnHost = try await hostLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }

        let future = try JSONEncoder().encode(Envelope(message: .end, version: Envelope.currentVersion + 1))
        try player.sendRaw(future, to: found.id)

        let version = try await hostLog.first(within: .seconds(10)) { event -> Int? in
            if case .failed(.incompatibleVersion(let v, let from)) = event, from == playerOnHost { v } else { nil }
        }
        #expect(version == Envelope.currentVersion + 1)
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerDisconnected(let p) = event, p == found.id { p } else { nil }
        }
        await host.stop(); await player.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func playerReconnectsToTheSameHostAfterADrop() async throws {
        let (host, hostLog, player, playerLog, found) = try await hostAndFoundGame("Reconnect")
        try await player.connect(to: found.id)
        let first = try await hostLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }

        let mark = playerLog.count
        host.dropConnection(to: first)
        _ = try await playerLog.first(within: .seconds(20), after: mark) { event -> PeerID? in
            if case .peerDisconnected(let p) = event, p == found.id { p } else { nil }
        }

        let reconnectMark = playerLog.count
        let hostMark = hostLog.count
        try await player.connect(to: found.id)  // same PeerID for the same host
        _ = try await playerLog.first(within: .seconds(20), after: reconnectMark) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }
        let second = try await hostLog.first(within: .seconds(10), after: hostMark) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        #expect(second != first, "the host sees a new connection; hello re-maps the player")
        await host.stop(); await player.stop()
    }

    /// The full stack the app runs: sessions + engines over real Network.framework.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sessionsJoinPlayARoundAndEnd() async throws {
        let name = uniqueSessionName("Session")
        let host = HostSession(hostID: PlayerID(rawValue: "h"), hostName: "Hana",
                               transport: NetworkTransport(displayName: "Hana"), sessionName: name)
        let pat = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat",
                                transport: NetworkTransport(displayName: "Pat"))
        await host.start()
        await pat.start()

        try await waitFor(.seconds(20)) { pat.hosts.contains { $0.sessionName == name } }
        await pat.join(try #require(pat.hosts.first { $0.sessionName == name }))
        try await waitFor(.seconds(20)) { pat.engine.status == .waiting }
        try await waitFor(.seconds(5)) { host.engine.players.map(\.name) == ["Hana", "Pat"] }

        await host.arm()
        try await waitFor(.seconds(5)) { pat.engine.status == .ready }
        pat.buzz()
        try await waitFor(.seconds(5)) { pat.engine.status == .ranked(position: 1, deltaMilliseconds: 0) }
        #expect(host.engine.round.winner?.playerID == PlayerID(rawValue: "p"))

        await host.end()
        try await waitFor(.seconds(10)) { pat.phase == .ended(.hostEnded) }
    }

    @MainActor
    private func waitFor(_ timeout: Duration, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw EventLog.Timeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Collects a transport's events on a background task so tests can wait for specific ones.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TransportEvent] = []
    private var task: Task<Void, Never>?

    struct Timeout: Error {}

    init(_ stream: AsyncStream<TransportEvent>) {
        task = Task { [weak self] in
            for await event in stream { self?.append(event) }
        }
    }

    deinit { task?.cancel() }

    private func append(_ event: TransportEvent) { lock.withLock { events.append(event) } }

    var count: Int { lock.withLock { events.count } }

    func count(where match: (TransportEvent) -> Bool) -> Int {
        lock.withLock { events.filter(match).count }
    }

    /// First event at index ≥ `after` that `match` maps to a value.
    func first<T>(within timeout: Duration, after start: Int = 0, _ match: (TransportEvent) -> T?) async throws -> T {
        let deadline = ContinuousClock.now + timeout
        var index = start
        while ContinuousClock.now < deadline {
            let snapshot = lock.withLock { events }
            while index < snapshot.count {
                if let value = match(snapshot[index]) { return value }
                index += 1
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Timeout()
    }
}
