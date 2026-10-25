import BuzzCore
import Foundation
import MultipeerConnectivity

/// `GameTransport` over Apple's MultipeerConnectivity (Wi-Fi, peer-to-peer Wi-Fi and Bluetooth).
///
/// Stage 0 ships only the contract and constants; the advertiser/browser/session wiring is
/// implemented in Stage 2 (see docs/roadmap.md).
public final class MultipeerTransport: GameTransport, @unchecked Sendable {
    /// Must match `NSBonjourServices` in the app's Info.plist (`_quickbuzz._tcp` / `_quickbuzz._udp`).
    public static let serviceType = "quickbuzz"
    /// Key in the advertiser's discovery info carrying the human-readable session name.
    public static let sessionNameKey = "session"

    public let localPeer: PeerID
    public let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let mcPeer: MCPeerID

    public init(displayName: String) {
        mcPeer = MCPeerID(displayName: displayName)
        localPeer = PeerID(rawValue: displayName)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public func startHosting(sessionName: String) async throws { throw TransportError.underlying("Stage 2") }
    public func startBrowsing() async throws { throw TransportError.underlying("Stage 2") }
    public func connect(to host: PeerID) async throws { throw TransportError.underlying("Stage 2") }
    public func send(_ message: GameMessage, to peers: [PeerID]) async throws { throw TransportError.notConnected }
    public func broadcast(_ message: GameMessage) async throws { throw TransportError.notConnected }
    public func stop() async { continuation.finish() }
}
