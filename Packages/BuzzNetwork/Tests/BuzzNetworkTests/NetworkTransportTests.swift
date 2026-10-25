import BuzzCore
import Foundation
import Network
import Testing
@testable import BuzzNetwork

@Suite("NetworkTransport")
struct NetworkTransportTests {
    @Test("service type is a valid Bonjour type: _name._tcp with a 1–15 char name")
    func serviceTypeIsValid() {
        let parts = NetworkTransport.serviceType.split(separator: ".")
        #expect(parts.count == 2)
        #expect(parts[1] == "_tcp")
        let name = parts[0].dropFirst()
        #expect(parts[0].first == "_")
        #expect((1...15).contains(name.count))
        #expect(name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }

    @Test func playerLimitIsTheGameLimit() {
        #expect(NetworkTransport.maxPlayers == SessionLimits.maxPlayers)
    }

    @Test func pendingConnectionsExpireBeforeThePlayerGivesUp() {
        #expect(NetworkTransport.connectionExpiry < .seconds(20))  // PlayerSession's default connectTimeout
    }

    @Test func localPeerIsLabelledWithDisplayName() {
        #expect(NetworkTransport(displayName: "Alice").localPeer.rawValue.hasPrefix("Alice#"))
        #expect(NetworkTransport(displayName: "  ").localPeer.rawValue.hasPrefix("Player#"))
    }

    @Test func sendingToUnknownPeerThrows() async {
        let t = NetworkTransport(displayName: "Alice")
        await #expect(throws: TransportError.peerUnknown(PeerID(rawValue: "ghost"))) {
            try await t.send(.end, to: [PeerID(rawValue: "ghost")])
        }
        try? await t.broadcast(.end)  // nobody connected: a no-op, not an error
    }

    @Test func connectingToAnUnknownHostThrows() async {
        let t = NetworkTransport(displayName: "Alice")
        await #expect(throws: TransportError.peerUnknown(PeerID(rawValue: "nobody"))) {
            try await t.connect(to: PeerID(rawValue: "nobody"))
        }
    }

    @Test func stopFinishesEventsAndIsIdempotent() async {
        let t = NetworkTransport(displayName: "Alice")
        await t.stop()
        await t.stop()
        var iterator = t.events.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        await #expect(throws: TransportError.self) { try await t.startHosting(sessionName: "x") }
        await #expect(throws: TransportError.self) { try await t.startBrowsing() }
    }
}

@Suite("Network parameters")
struct NetworkParametersTests {
    @Test func peerToPeerWiFiIsAllowed() {
        #expect(NetworkParameters.make().includePeerToPeer)
    }

    @Test func stackIsWebSocketOverTLSOverTCPWithNoDelay() throws {
        let stack = NetworkParameters.make().defaultProtocolStack
        #expect(stack.applicationProtocols.first is NWProtocolWebSocket.Options, "WebSocket outermost")
        #expect(stack.applicationProtocols.contains { $0 is NWProtocolTLS.Options }, "TLS under it")
        let tcp = try #require(stack.transportProtocol as? NWProtocolTCP.Options)
        #expect(tcp.noDelay)
        #expect(tcp.enableKeepalive)
    }

    @Test func presharedKeyIsAFixed256BitValue() {
        #expect(NetworkParameters.presharedKey.count == 32)
        #expect(NetworkParameters.presharedKey == NetworkParameters.presharedKey)
    }

    @Test func txtRecordRoundTripsDiscoveryInfo() {
        let record = NWTXTRecord(DiscoveryInfo.make(sessionName: "Quiz night"))
        #expect(DiscoveryInfo.sessionName(from: record.dictionary, fallback: "x") == "Quiz night")
        #expect(DiscoveryInfo.isCompatible(record.dictionary))
    }
}
