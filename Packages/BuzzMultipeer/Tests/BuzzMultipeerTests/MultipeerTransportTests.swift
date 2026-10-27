import BuzzCore
import Foundation
import MultipeerConnectivity
import Testing
@testable import BuzzMultipeer

@Suite("MultipeerTransport")
struct MultipeerTransportTests {
    @Test("service type is a valid Bonjour name: 1–15 chars, lowercase letters, digits, hyphens")
    func serviceTypeIsValid() {
        let type = MultipeerTransport.serviceType
        #expect((1...15).contains(type.count))
        #expect(type.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }

    @Test func sessionCapacityMatchesTheGameLimit() {
        #expect(MultipeerTransport.maxPlayers == SessionLimits.maxPlayers)
    }

    @Test func invitationTimesOutBeforeThePlayerSessionDoes() {
        // PlayerSession's default connectTimeout is 20 s; the transport must report first.
        #expect(MultipeerTransport.invitationTimeout < 20)
    }

    @Test func localPeerIsLabelledWithDisplayName() {
        let t = MultipeerTransport(displayName: "Alice")
        #expect(t.localPeer.rawValue.hasPrefix("Alice#"))
    }

    @Test func emptyOrHugeNamesDoNotCrash() {
        _ = MultipeerTransport(displayName: "   ")
        _ = MultipeerTransport(displayName: String(repeating: "🐝", count: 100))
    }

    @Test func sendingToUnknownPeerThrows() async {
        let t = MultipeerTransport(displayName: "Alice")
        await #expect(throws: TransportError.peerUnknown(PeerID(rawValue: "ghost"))) {
            try await t.send(.end, to: [PeerID(rawValue: "ghost")])
        }
        try? await t.broadcast(.end)  // no peers: a no-op, not an error
    }

    @Test func connectRequiresBrowsing() async {
        let t = MultipeerTransport(displayName: "Alice")
        await #expect(throws: TransportError.self) {
            try await t.connect(to: PeerID(rawValue: "anyone"))
        }
    }

    @Test func stopFinishesEventsAndIsIdempotent() async {
        let t = MultipeerTransport(displayName: "Alice")
        await t.stop()
        await t.stop()
        var iterator = t.events.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        await #expect(throws: TransportError.self) { try await t.startHosting(sessionName: "x") }
    }
}

@Suite("Multipeer helpers")
struct PeerSupportTests {
    @Test func registryKeepsSameNamedMCPeersDistinct() {
        var registry = PeerRegistry<MCPeerID>()
        let a = MCPeerID(displayName: "Sam")
        let b = MCPeerID(displayName: "Sam")
        let idA = registry.peerID(for: a, displayName: a.displayName)
        let idB = registry.peerID(for: b, displayName: b.displayName)
        #expect(idA != idB)
        #expect(registry.key(for: idA) == a)
        #expect(registry.key(for: idB) == b)
    }

    @Test func invitationContextCarriesTheVersion() {
        #expect(InvitationContext.isCompatible(InvitationContext.current))
        #expect(!InvitationContext.isCompatible(nil))
        #expect(!InvitationContext.isCompatible(Data("v=999".utf8)))
    }

    @Test func pendingInvitationsExpireBeforeThePlayerGivesUp() {
        #expect(MultipeerTransport.invitationExpiry > .seconds(MultipeerTransport.invitationTimeout))
        #expect(MultipeerTransport.invitationExpiry < .seconds(20))
    }
}
