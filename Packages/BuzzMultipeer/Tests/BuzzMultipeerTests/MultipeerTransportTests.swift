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

    @Test func sessionHoldsSevenPlayersPlusHost() {
        #expect(MultipeerTransport.maxPlayers == 7)
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

@Suite("Peer helpers")
struct PeerSupportTests {
    @Test func registryKeepsSameNamedPeersDistinct() {
        var registry = PeerRegistry<MCPeerID>()
        let a = MCPeerID(displayName: "Sam")
        let b = MCPeerID(displayName: "Sam")
        let idA = registry.peerID(for: a, displayName: a.displayName)
        let idB = registry.peerID(for: b, displayName: b.displayName)
        #expect(idA != idB)
        #expect(registry.peerID(for: a, displayName: "renamed") == idA, "stable once minted")
        #expect(registry.key(for: idA) == a)
        #expect(registry.key(for: idB) == b)
        #expect(registry.key(for: PeerID(rawValue: "nope")) == nil)
    }

    @Test func displayNameIsSanitized() {
        #expect(PeerName.sanitized("  Ann  ") == "Ann")
        #expect(PeerName.sanitized("") == "Player")
        #expect(PeerName.sanitized(" \n ") == "Player")
        let long = PeerName.sanitized(String(repeating: "é", count: 60))  // 2 bytes each
        #expect(long.utf8.count <= PeerName.maxDisplayNameBytes)
        #expect(long.count == 31)
    }

    @Test func truncationNeverSplitsCharacters() {
        let flags = String(repeating: "🇮🇳", count: 10)  // 8 bytes per flag
        let cut = PeerName.truncated(flags, maxBytes: 20)
        #expect(cut == "🇮🇳🇮🇳")
    }

    @Test func discoveryInfoRoundTrip() {
        let info = DiscoveryInfo.make(sessionName: "Quiz night")
        #expect(info[DiscoveryInfo.sessionNameKey] == "Quiz night")
        #expect(info[DiscoveryInfo.versionKey] == String(Envelope.currentVersion))
        #expect(DiscoveryInfo.sessionName(from: info, fallback: "x") == "Quiz night")
        #expect(DiscoveryInfo.sessionName(from: nil, fallback: "Bob's iPhone") == "Bob's iPhone")
        #expect(DiscoveryInfo.sessionName(from: [DiscoveryInfo.sessionNameKey: ""], fallback: "fb") == "fb")
    }

    @Test func versionCompatibility() {
        #expect(DiscoveryInfo.isCompatible(DiscoveryInfo.make(sessionName: "g")))
        #expect(DiscoveryInfo.isCompatible(nil), "unversioned hosts are given the benefit of the doubt")
        #expect(!DiscoveryInfo.isCompatible([DiscoveryInfo.versionKey: "999"]))
        #expect(InvitationContext.isCompatible(InvitationContext.current))
        #expect(!InvitationContext.isCompatible(nil))
        #expect(!InvitationContext.isCompatible(Data("v=999".utf8)))
    }

    @Test func pendingInvitationsExpireBeforeThePlayerGivesUp() {
        #expect(MultipeerTransport.invitationExpiry > .seconds(MultipeerTransport.invitationTimeout))
        #expect(MultipeerTransport.invitationExpiry < .seconds(20))
    }

    @Test func discoveryInfoFitsBonjourLimits() {
        let info = DiscoveryInfo.make(sessionName: String(repeating: "W", count: 1_000))
        for (key, value) in info {
            #expect("\(key)=\(value)".utf8.count <= 255)
        }
    }
}
