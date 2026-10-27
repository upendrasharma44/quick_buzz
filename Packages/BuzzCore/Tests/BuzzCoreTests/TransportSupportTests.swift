import Foundation
import Testing
@testable import BuzzCore

@Suite("Transport helpers")
struct TransportSupportTests {
    @Test func registryMintsDistinctStableHandles() {
        var registry = PeerRegistry<String>()
        let a = registry.peerID(for: "endpoint-a", displayName: "Sam")
        let b = registry.peerID(for: "endpoint-b", displayName: "Sam")
        #expect(a != b, "same display name, different peers")
        #expect(registry.peerID(for: "endpoint-a", displayName: "renamed") == a, "stable once minted")
        #expect(registry.key(for: a) == "endpoint-a")
        #expect(registry.key(for: PeerID(rawValue: "nope")) == nil)
    }

    @Test func registryForgetsRemovedPeers() {
        var registry = PeerRegistry<String>()
        let a = registry.peerID(for: "conn-1", displayName: "Ava")
        registry.remove(a)
        #expect(registry.key(for: a) == nil)
        #expect(registry.peerID(for: "conn-1", displayName: "Ava") != a, "a new connection gets a new handle")
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
        #expect(PeerName.truncated(flags, maxBytes: 20) == "🇮🇳🇮🇳")
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
    }

    @Test func discoveryInfoFitsBonjourLimits() {
        let info = DiscoveryInfo.make(sessionName: String(repeating: "W", count: 1_000))
        for (key, value) in info {
            #expect("\(key)=\(value)".utf8.count <= 255)
        }
    }

    @Test func gameLimitIsSevenPlayers() {
        #expect(SessionLimits.maxPlayers == 7)
    }
}
