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

    @Test func localPeerUsesDisplayName() {
        let t = MultipeerTransport(displayName: "Alice's iPhone")
        #expect(t.localPeer.rawValue == "Alice's iPhone")
    }
}
