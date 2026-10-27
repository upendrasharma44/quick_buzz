import Foundation

/// Transport-level identity of a connected device. Distinct from `PlayerID`: the host learns
/// the mapping from `PeerID` to `PlayerID` through the `hello` message.
///
/// A `PeerID` is a local handle minted by the transport. It is unique within one transport
/// instance and is never sent over the wire, so two people with the same display name never collide.
public struct PeerID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// A host advertised on the local network.
public struct DiscoveredHost: Hashable, Sendable, Identifiable {
    public let id: PeerID
    public let sessionName: String
    /// `false` when the host advertises a different protocol version; joining it would fail.
    public let isCompatible: Bool

    public init(id: PeerID, sessionName: String, isCompatible: Bool = true) {
        self.id = id
        self.sessionName = sessionName
        self.isCompatible = isCompatible
    }
}

public enum TransportError: Error, Hashable, Sendable, LocalizedError {
    case notConnected
    case peerUnknown(PeerID)
    /// An invitation to `PeerID` was declined, timed out, or dropped before connecting.
    case connectionFailed(PeerID)
    /// `PeerID` sent a frame encoded with protocol version `Int`, which we cannot read.
    case incompatibleVersion(Int, from: PeerID)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected."
        case .peerUnknown: "That device is no longer available."
        case .connectionFailed: "Couldn't connect. Make sure both phones are nearby and try again."
        case .incompatibleVersion: "The other phone is running a different version of BuzzLight."
        case .underlying(let message): message
        }
    }
}

public enum TransportEvent: Sendable {
    case hostFound(DiscoveredHost)
    case hostLost(PeerID)
    case peerConnected(PeerID)
    case peerDisconnected(PeerID)
    /// `receivedAt` is stamped by the transport the moment the frame arrives, before decoding and
    /// before any actor hop, so queueing delays on the consumer side never distort buzz deltas.
    case message(GameMessage, from: PeerID, receivedAt: ContinuousClock.Instant)
    case failed(TransportError)
}

/// The only thing the engines know about networking. Implementations:
/// `LoopbackTransport` (in-process, tests/previews), `NetworkTransport` (BuzzNetwork),
/// and later an internet relay (BuzzRelay).
///
/// A transport instance serves one game session: create it, use it, `stop()` it, discard it.
public protocol GameTransport: AnyObject, Sendable {
    var localPeer: PeerID { get }
    /// Single-consumer stream of everything that happens on the wire. Finishes after `stop()`.
    var events: AsyncStream<TransportEvent> { get }

    /// Advertise a session that nearby players can discover. No-op while already advertising;
    /// the transport itself resumes advertising when the app returns to the foreground.
    func startHosting(sessionName: String) async throws
    /// Look for nearby hosts; results arrive as `.hostFound` / `.hostLost`. No-op while already
    /// browsing. Starting again after `stopBrowsing()` re-reports every host currently visible.
    func startBrowsing() async throws
    /// Stop looking for hosts (saves radio time once joined). Existing connections stay up.
    func stopBrowsing() async
    /// Ask to join a host. Requires `startBrowsing()` first; if the current browse has not found the
    /// host yet, the request waits until it does. Success is signalled by `.peerConnected(host)`
    /// (immediately if already connected), failure by `.failed(.connectionFailed(host))`.
    /// Repeated calls while a request is pending are ignored.
    func connect(to host: PeerID) async throws
    func send(_ message: GameMessage, to peers: [PeerID]) async throws
    func broadcast(_ message: GameMessage) async throws
    /// Drop the link to one peer (e.g. it went silent). Emits `.peerDisconnected(peer)` if it was
    /// connected; unknown peers are ignored.
    func disconnect(_ peer: PeerID) async
    /// Stop advertising/browsing, drop every connection and finish `events`. Idempotent.
    func stop() async
}

/// Who an outbound message from an engine is addressed to.
public enum Recipients: Hashable, Sendable {
    case all
    case peers([PeerID])
}

/// A message an engine wants delivered. The session layer hands it to a `GameTransport`.
public struct Outbound: Hashable, Sendable {
    public let message: GameMessage
    public let to: Recipients

    public init(_ message: GameMessage, to: Recipients) {
        self.message = message
        self.to = to
    }

    public static func all(_ message: GameMessage) -> Outbound { Outbound(message, to: .all) }
    public static func peer(_ peer: PeerID, _ message: GameMessage) -> Outbound { Outbound(message, to: .peers([peer])) }
}

extension GameTransport {
    public func deliver(_ outbound: Outbound) async throws {
        switch outbound.to {
        case .all: try await broadcast(outbound.message)
        case .peers(let peers): try await send(outbound.message, to: peers)
        }
    }

    public func deliver(_ outbounds: [Outbound]) async throws {
        for outbound in outbounds { try await deliver(outbound) }
    }
}
