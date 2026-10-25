import BuzzCore
import Foundation
import Testing
@testable import BuzzMultipeer

/// Real MultipeerConnectivity between two transports in this process (Bonjour over loopback).
/// Opt-in because it needs the local network and is too slow/flaky for CI:
///
///     QUICKBUZZ_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer
@Suite(
    "Live Multipeer (opt-in)",
    .enabled(if: ProcessInfo.processInfo.environment["QUICKBUZZ_LIVE_MULTIPEER"] != nil),
    .serialized
)
struct LiveMultipeerTests {
    @Test(.timeLimit(.minutes(1)))
    func hostAndPlayerDiscoverConnectAndExchangeMessages() async throws {
        let host = MultipeerTransport(displayName: "LiveHost")
        let player = MultipeerTransport(displayName: "LivePlayer")
        let hostLog = EventLog(host.events)
        let playerLog = EventLog(player.events)
        defer { Task { await host.stop(); await player.stop() } }

        let sessionName = "Live test \(UUID().uuidString.prefix(4))"
        try await host.startHosting(sessionName: sessionName)
        try await player.startBrowsing()

        let found = try await playerLog.first(within: .seconds(20)) { event -> DiscoveredHost? in
            if case .hostFound(let h) = event, h.sessionName == sessionName { h } else { nil }
        }
        try await player.connect(to: found.id)

        let playerAsSeenByHost = try await hostLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }
        await player.stopBrowsing()

        let me = PlayerID(rawValue: "live")
        try await player.broadcast(.hello(playerID: me, name: "LivePlayer"))
        let hello = try await hostLog.first(within: .seconds(10)) { event -> GameMessage? in
            if case .message(let m, let from, _) = event, from == playerAsSeenByHost { m } else { nil }
        }
        #expect(hello == .hello(playerID: me, name: "LivePlayer"))

        try await host.send(.armed(round: RoundID(1)), to: [playerAsSeenByHost])
        let armed = try await playerLog.first(within: .seconds(10)) { event -> GameMessage? in
            if case .message(let m, _, _) = event { m } else { nil }
        }
        #expect(armed == .armed(round: RoundID(1)))

        await host.stop()
        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerDisconnected(let p) = event, p == found.id { p } else { nil }
        }
    }

    /// Regression: MultipeerConnectivity silently drops an invitation sent through a browser that
    /// has not reported the peer yet. The transport must hold it until the new browser finds the host.
    @Test(.timeLimit(.minutes(1)))
    func inviteThroughAFreshBrowserIsDeferredUntilFound() async throws {
        let host = MultipeerTransport(displayName: "LiveHost2")
        let player = MultipeerTransport(displayName: "LivePlayer2")
        let hostLog = EventLog(host.events)
        let playerLog = EventLog(player.events)
        defer { Task { await host.stop(); await player.stop() } }

        let sessionName = "Fresh browser \(UUID().uuidString.prefix(4))"
        try await host.startHosting(sessionName: sessionName)
        try await player.startBrowsing()
        let found = try await playerLog.first(within: .seconds(20)) { event -> DiscoveredHost? in
            if case .hostFound(let h) = event, h.sessionName == sessionName { h } else { nil }
        }
        #expect(found.isCompatible)

        // New browser, then invite immediately — before it has re-found the host.
        await player.stopBrowsing()
        try await player.startBrowsing()
        try await player.connect(to: found.id)

        _ = try await playerLog.first(within: .seconds(20)) { event -> PeerID? in
            if case .peerConnected(let p) = event, p == found.id { p } else { nil }
        }
        _ = try await hostLog.first(within: .seconds(5)) { event -> PeerID? in
            if case .peerConnected(let p) = event { p } else { nil }
        }
    }

    /// The full stack the app runs: sessions + engines over real MultipeerConnectivity.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sessionsJoinSyncRosterAndEnd() async throws {
        let sessionName = "Live session \(UUID().uuidString.prefix(4))"
        let host = HostSession(hostID: PlayerID(rawValue: "h"), hostName: "Hana",
                               transport: MultipeerTransport(displayName: "Hana"), sessionName: sessionName)
        let pat = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat",
                                transport: MultipeerTransport(displayName: "Pat"))
        await host.start()
        await pat.start()

        try await waitFor(.seconds(20)) { pat.hosts.contains { $0.sessionName == sessionName } }
        await pat.join(try #require(pat.hosts.first { $0.sessionName == sessionName }))
        try await waitFor(.seconds(20)) { pat.engine.status == .waiting }
        try await waitFor(.seconds(5)) { host.engine.players.map(\.name) == ["Hana", "Pat"] }
        #expect(pat.engine.players.map(\.name) == ["Hana", "Pat"])

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

    func first<T>(within timeout: Duration, _ match: (TransportEvent) -> T?) async throws -> T {
        let deadline = ContinuousClock.now + timeout
        var index = 0
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
