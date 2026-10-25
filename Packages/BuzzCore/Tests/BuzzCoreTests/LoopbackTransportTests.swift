import Foundation
import Testing
@testable import BuzzCore

/// End-to-end: a host engine and two player engines talking through `LoopbackTransport`.
@MainActor
@Suite("Loopback integration")
struct LoopbackTransportTests {
    @Test func hostAndTwoPlayersPlayARound() async throws {
        let network = LoopbackNetwork()
        let hostTransport = await network.makeTransport(name: "host")
        let aliceTransport = await network.makeTransport(name: "alice")
        let bobTransport = await network.makeTransport(name: "bob")

        let host = HostEngine(hostID: PlayerID(rawValue: "H"), hostName: "Host")
        let alice = PlayerEngine(id: PlayerID(rawValue: "A"), name: "Alice")
        let bob = PlayerEngine(id: PlayerID(rawValue: "B"), name: "Bob")

        var hostEvents = hostTransport.events.makeAsyncIterator()
        var aliceEvents = aliceTransport.events.makeAsyncIterator()
        var bobEvents = bobTransport.events.makeAsyncIterator()

        try await hostTransport.startHosting(sessionName: "Host's game")
        try await aliceTransport.startBrowsing()
        guard case .hostFound(let found)? = await aliceEvents.next() else { Issue.record("no host found"); return }
        #expect(found.sessionName == "Host's game")

        // Alice joins.
        try await aliceTransport.connect(to: found.id)
        guard case .peerConnected? = await hostEvents.next() else { Issue.record("host saw no peer"); return }
        guard case .peerConnected? = await aliceEvents.next() else { Issue.record("alice not connected"); return }
        try await aliceTransport.deliver(alice.connected())
        guard case .message(let hello, let from, _)? = await hostEvents.next() else { Issue.record("no hello"); return }
        try await hostTransport.deliver(host.receive(hello, from: from))
        guard case .message(let welcome, _, _)? = await aliceEvents.next() else { Issue.record("no welcome"); return }
        _ = alice.receive(welcome)
        guard case .message(let roster1, _, _)? = await aliceEvents.next() else { Issue.record("no roster"); return }
        _ = alice.receive(roster1)
        #expect(alice.status == .waiting)
        #expect(alice.players.count == 2)

        // Bob joins (no browsing needed; connect directly).
        try await bobTransport.connect(to: hostTransport.localPeer)
        _ = await hostEvents.next()
        _ = await bobEvents.next()
        try await bobTransport.deliver(bob.connected())
        guard case .message(let helloB, let fromB, _)? = await hostEvents.next() else { Issue.record("no hello B"); return }
        try await hostTransport.deliver(host.receive(helloB, from: fromB))
        guard case .message(let welcomeB, _, _)? = await bobEvents.next() else { Issue.record("no welcome B"); return }
        _ = bob.receive(welcomeB)
        guard case .message(let rosterB, _, _)? = await bobEvents.next() else { Issue.record("no roster B"); return }
        _ = bob.receive(rosterB)
        guard case .message(let rosterA, _, _)? = await aliceEvents.next() else { Issue.record("no roster A"); return }
        _ = alice.receive(rosterA)
        #expect(alice.players.count == 3)
        #expect(bob.players.count == 3)

        // Arm, then Bob buzzes before Alice.
        try await hostTransport.deliver(host.arm())
        guard case .message(let armedA, _, _)? = await aliceEvents.next() else { Issue.record("no armed A"); return }
        guard case .message(let armedB, _, _)? = await bobEvents.next() else { Issue.record("no armed B"); return }
        _ = alice.receive(armedA)
        _ = bob.receive(armedB)
        #expect(alice.status == .ready)

        try await bobTransport.deliver(bob.buzz())
        try await aliceTransport.deliver(alice.buzz())
        for _ in 0..<2 {
            guard case .message(let buzz, let from, _)? = await hostEvents.next() else { Issue.record("no buzz"); return }
            try await hostTransport.deliver(host.receive(buzz, from: from))
        }
        #expect(host.round.ranking.map(\.playerID.rawValue) == ["B", "A"])

        // Both players receive two result updates; the last one is complete.
        for _ in 0..<2 {
            guard case .message(let r, _, _)? = await aliceEvents.next() else { Issue.record("no result A"); return }
            _ = alice.receive(r)
            guard case .message(let rb, _, _)? = await bobEvents.next() else { Issue.record("no result B"); return }
            _ = bob.receive(rb)
        }
        #expect(bob.status == .ranked(position: 1, deltaMilliseconds: 0))
        guard case .ranked(let position, _) = alice.status else { Issue.record("alice not ranked"); return }
        #expect(position == 2)

        // Host leaves: players are disconnected and hosts are lost.
        await hostTransport.stop()
        guard case .hostLost(let lost)? = await aliceEvents.next(), lost == hostTransport.localPeer else { Issue.record("host not lost"); return }
        guard case .peerDisconnected? = await aliceEvents.next() else { Issue.record("alice not disconnected"); return }
        alice.disconnected()
        #expect(alice.status == .ended)
    }

    @Test func contractStartBrowsingIsIdempotentAndConnectReconfirms() async throws {
        let network = LoopbackNetwork()
        let host = await network.makeTransport(name: "host")
        let player = await network.makeTransport(name: "p")
        try await host.startHosting(sessionName: "g")
        var events = player.events.makeAsyncIterator()

        try await player.startBrowsing()
        guard case .hostFound? = await events.next() else { Issue.record("no host"); return }
        try await player.startBrowsing()  // already browsing: no duplicate report
        try await player.connect(to: host.localPeer)
        guard case .peerConnected? = await events.next() else { Issue.record("not connected"); return }
        try await player.connect(to: host.localPeer)  // already connected: re-confirmed
        guard case .peerConnected? = await events.next() else { Issue.record("not re-confirmed"); return }

        await player.stopBrowsing()
        try await player.startBrowsing()  // restarted after a stop: re-reports
        guard case .hostFound? = await events.next() else { Issue.record("no re-report"); return }
    }

    @Test func eventsFinishAfterStop() async {
        let network = LoopbackNetwork()
        let t = await network.makeTransport(name: "x")
        await t.stop()
        await t.stop()
        var events = t.events.makeAsyncIterator()
        #expect(await events.next() == nil)
    }

    @Test func connectingToUnknownHostFails() async {
        let network = LoopbackNetwork()
        let t = await network.makeTransport(name: "x")
        await #expect(throws: TransportError.self) {
            try await t.connect(to: PeerID(rawValue: "nobody"))
        }
    }
}
