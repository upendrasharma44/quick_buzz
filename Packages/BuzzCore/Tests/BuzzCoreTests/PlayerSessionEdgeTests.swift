import Foundation
import Testing
@testable import BuzzCore

/// Player-session behaviour that depends on transport details LoopbackTransport does not model:
/// MultipeerConnectivity's full mesh, version mismatches, and app suspension.
@MainActor
@Suite("PlayerSession edge cases")
struct PlayerSessionEdgeTests {
    let hostPeer = PeerID(rawValue: "host")
    let otherPlayer = PeerID(rawValue: "other-player")
    var host: DiscoveredHost { DiscoveredHost(id: hostPeer, sessionName: "Hana's game") }

    func joinedSession(
        reconnectTimeout: Duration = .seconds(5)
    ) async -> (PlayerSession, ScriptedTransport) {
        let transport = ScriptedTransport()
        let session = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: transport,
                                    reconnectTimeout: reconnectTimeout, retryDelay: .milliseconds(10))
        await session.start()
        transport.emit(.hostFound(host))
        _ = await eventually { !session.hosts.isEmpty }
        await session.join(host)
        _ = await eventually { session.phase == .joined(host) }
        let snapshot = SessionSnapshot(players: [Player(id: PlayerID(rawValue: "h"), name: "Hana", isHost: true)],
                                       round: RoundState(id: RoundID(1)))
        transport.emit(.message(.welcome(snapshot: snapshot), from: hostPeer, receivedAt: .now))
        _ = await eventually { session.engine.status == .waiting }
        return (session, transport)
    }

    @Test func playerTrafficGoesToTheHostOnly() async {
        let (session, transport) = await joinedSession()
        transport.emit(.message(.ping(id: 3), from: hostPeer, receivedAt: .now))
        #expect(await eventually { transport.sent.count == 2 })
        #expect(transport.sent == [
            .init(message: .hello(playerID: PlayerID(rawValue: "p"), name: "Pat"), to: [hostPeer]),
            .init(message: .pong(id: 3), to: [hostPeer]),
        ])
        _ = session
    }

    @Test func versionMismatchFromAnotherPlayerIsIgnored() async {
        let (session, transport) = await joinedSession()
        transport.emit(.failed(.incompatibleVersion(2, from: otherPlayer)))
        transport.emit(.message(.ping(id: 1), from: hostPeer, receivedAt: .now))  // a marker event
        #expect(await eventually { transport.sent.count == 2 })
        #expect(session.phase == .joined(host))
    }

    @Test func versionMismatchFromTheHostEndsTheGame() async {
        let (session, transport) = await joinedSession()
        transport.emit(.failed(.incompatibleVersion(2, from: hostPeer)))
        #expect(await eventually { session.phase == .ended(.incompatibleVersion) })
    }

    @Test func messagesFromOtherPlayersAreIgnored() async {
        let (session, transport) = await joinedSession()
        transport.emit(.message(.kick, from: otherPlayer, receivedAt: .now))
        transport.emit(.message(.end, from: otherPlayer, receivedAt: .now))
        transport.emit(.message(.ping(id: 1), from: hostPeer, receivedAt: .now))
        #expect(await eventually { transport.sent.count == 2 })
        #expect(session.phase == .joined(host))
    }

    @Test func incompatibleHostCannotBeJoined() async {
        let transport = ScriptedTransport()
        let session = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: transport)
        await session.start()
        let newer = DiscoveredHost(id: hostPeer, sessionName: "Future game", isCompatible: false)
        await session.join(newer)
        #expect(session.phase == .browsing)
        #expect(transport.connectCalls.isEmpty)
        #expect(session.notice?.contains("different version") == true)
    }

    @Test func dropClearsStaleHostsAndRetriesImmediately() async {
        let (session, transport) = await joinedSession()
        transport.emit(.hostFound(DiscoveredHost(id: otherPlayer, sessionName: "Other game")))
        _ = await eventually { session.hosts.count == 2 }
        let connectsBefore = transport.connectCalls.count

        transport.emit(.peerDisconnected(hostPeer))
        // ScriptedTransport auto-accepts, so the immediate retry rejoins straight away.
        #expect(await eventually { transport.connectCalls.count > connectsBefore })
        #expect(await eventually { session.phase == .joined(host) })
        #expect(session.hosts.isEmpty, "list restarted on drop")
    }

    @Test func reconnectDeadlineIsPausedWhileBackgrounded() async {
        let transport = ScriptedTransport(autoConnect: false)
        let session = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: transport,
                                    connectTimeout: .seconds(5), reconnectTimeout: .milliseconds(100),
                                    retryDelay: .milliseconds(10))
        await session.start()
        await session.join(host)
        transport.emit(.peerConnected(hostPeer))
        _ = await eventually { session.phase == .joined(host) }

        // The system drops the link while the app is going to the background.
        session.sceneDidEnterBackground()
        transport.emit(.peerDisconnected(hostPeer))
        _ = await eventually { session.phase == .reconnecting(host) }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(session.phase == .reconnecting(host), "deadline must not run while suspended")

        // Back in the foreground: a fresh deadline starts and a retry goes out.
        let connectsBefore = transport.connectCalls.count
        await session.sceneDidBecomeActive()
        #expect(transport.connectCalls.count > connectsBefore)
        #expect(await eventually { session.phase == .ended(.connectionLost) })
    }

    @Test func backgroundingDuringAReconnectStopsTheClock() async {
        let transport = ScriptedTransport(autoConnect: false)
        let session = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: transport,
                                    reconnectTimeout: .milliseconds(150), retryDelay: .milliseconds(10))
        await session.start()
        await session.join(host)
        transport.emit(.peerConnected(hostPeer))
        _ = await eventually { session.phase == .joined(host) }

        transport.emit(.peerDisconnected(hostPeer))
        _ = await eventually { session.phase == .reconnecting(host) }
        session.sceneDidEnterBackground()
        try? await Task.sleep(for: .milliseconds(400))
        #expect(session.phase == .reconnecting(host))

        // Host is back by the time the player returns.
        await session.sceneDidBecomeActive()
        transport.emit(.peerConnected(hostPeer))
        #expect(await eventually { session.phase == .joined(host) })
    }

    @Test func lateConnectionAfterJoinTimeoutIsUsableOnRetry() async {
        let transport = ScriptedTransport(autoConnect: false)
        let session = PlayerSession(playerID: PlayerID(rawValue: "p"), name: "Pat", transport: transport,
                                    connectTimeout: .milliseconds(30))
        await session.start()
        await session.join(host)
        #expect(await eventually { session.phase == .browsing })
        // The link completes after we gave up; ignored while browsing…
        transport.emit(.peerConnected(hostPeer))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.phase == .browsing)
        // …and the next attempt is confirmed by the transport straight away.
        await session.join(host)
        transport.emit(.peerConnected(hostPeer))
        #expect(await eventually { session.phase == .joined(host) })
    }
}
