import Foundation

/// Transport-level identity of a connected device. Distinct from `PlayerID`: the host learns
/// the mapping from `PeerID` to `PlayerID` through the `hello` message.
public struct PeerID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// A host advertised on the local network.
public struct DiscoveredHost: Hashable, Sendable, Identifiable {
    public let id: PeerID
    public let sessionName: String

    public init(id: PeerID, sessionName: String) {
        self.id = id
        self.sessionName = sessionName
    }
}

public enum TransportError: Error, Sendable {
    case notConnected
    case peerUnknown(PeerID)
    case underlying(String)
}

public enum TransportEvent: Sendable {
    case hostFound(DiscoveredHost)
    case hostLost(PeerID)
    case peerConnected(PeerID)
    case peerDisconnected(PeerID)
    case message(GameMessage, from: PeerID)
    case failed(TransportError)
}

/// The only thing the engines know about networking. Implementations:
/// `LoopbackTransport` (in-process, tests/previews), `MultipeerTransport` (BuzzMultipeer),
/// and later an internet relay (BuzzRelay).
public protocol GameTransport: AnyObject, Sendable {
    var localPeer: PeerID { get }
    /// Single-consumer stream of everything that happens on the wire.
    var events: AsyncStream<TransportEvent> { get }

    /// Advertise a session that nearby players can discover.
    func startHosting(sessionName: String) async throws
    /// Look for nearby hosts; results arrive as `.hostFound` / `.hostLost`.
    func startBrowsing() async throws
    /// Ask to join a discovered host. Completion is signalled by `.peerConnected(host)`.
    func connect(to host: PeerID) async throws
    func send(_ message: GameMessage, to peers: [PeerID]) async throws
    func broadcast(_ message: GameMessage) async throws
    /// Stop advertising/browsing and drop every connection.
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
