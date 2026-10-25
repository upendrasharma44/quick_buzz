import Foundation

/// In-process "network" shared by several `LoopbackTransport`s. Lets tests and SwiftUI previews
/// run a host and players in one process with real message passing but no sockets.
public actor LoopbackNetwork {
    private var transports: [PeerID: LoopbackTransport] = [:]
    private var hosts: [PeerID: String] = [:]
    private var links: Set<Link> = []

    private struct Link: Hashable { let a: PeerID; let b: PeerID
        init(_ x: PeerID, _ y: PeerID) { (a, b) = x.rawValue < y.rawValue ? (x, y) : (y, x) }
        func contains(_ p: PeerID) -> Bool { a == p || b == p }
        func other(than p: PeerID) -> PeerID { a == p ? b : a }
    }

    public init() {}

    public func makeTransport(name: String) -> LoopbackTransport {
        let t = LoopbackTransport(localPeer: PeerID(rawValue: name), network: self)
        transports[t.localPeer] = t
        return t
    }

    fileprivate func advertise(_ peer: PeerID, sessionName: String) {
        hosts[peer] = sessionName
        let host = DiscoveredHost(id: peer, sessionName: sessionName)
        for (id, t) in transports where id != peer && t.isBrowsing { t.emit(.hostFound(host)) }
    }

    fileprivate func browse(_ peer: PeerID) {
        guard let t = transports[peer] else { return }
        for (hostID, name) in hosts where hostID != peer {
            t.emit(.hostFound(DiscoveredHost(id: hostID, sessionName: name)))
        }
    }

    fileprivate func connect(_ from: PeerID, to host: PeerID) throws {
        guard hosts[host] != nil, let h = transports[host], let f = transports[from] else {
            throw TransportError.peerUnknown(host)
        }
        links.insert(Link(from, host))
        h.emit(.peerConnected(from))
        f.emit(.peerConnected(host))
    }

    fileprivate func send(_ message: GameMessage, from: PeerID, to peers: [PeerID]) throws {
        for p in peers {
            guard links.contains(Link(from, p)), let t = transports[p] else { throw TransportError.peerUnknown(p) }
            t.emit(.message(message, from: from))
        }
    }

    fileprivate func broadcast(_ message: GameMessage, from: PeerID) {
        for link in links where link.contains(from) {
            transports[link.other(than: from)]?.emit(.message(message, from: from))
        }
    }

    fileprivate func stop(_ peer: PeerID) {
        if hosts.removeValue(forKey: peer) != nil {
            for (id, t) in transports where id != peer { t.emit(.hostLost(peer)) }
        }
        for link in links where link.contains(peer) {
            links.remove(link)
            transports[link.other(than: peer)]?.emit(.peerDisconnected(peer))
        }
    }
}

public final class LoopbackTransport: GameTransport, @unchecked Sendable {
    public let localPeer: PeerID
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let network: LoopbackNetwork
    private let lock = NSLock()
    private var _isBrowsing = false

    fileprivate var isBrowsing: Bool { lock.withLock { _isBrowsing } }

    fileprivate init(localPeer: PeerID, network: LoopbackNetwork) {
        self.localPeer = localPeer
        self.network = network
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    fileprivate func emit(_ event: TransportEvent) { continuation.yield(event) }

    public func startHosting(sessionName: String) async throws {
        await network.advertise(localPeer, sessionName: sessionName)
    }

    public func startBrowsing() async throws {
        lock.withLock { _isBrowsing = true }
        await network.browse(localPeer)
    }

    public func connect(to host: PeerID) async throws {
        try await network.connect(localPeer, to: host)
    }

    public func send(_ message: GameMessage, to peers: [PeerID]) async throws {
        try await network.send(message, from: localPeer, to: peers)
    }

    public func broadcast(_ message: GameMessage) async throws {
        await network.broadcast(message, from: localPeer)
    }

    public func stop() async {
        lock.withLock { _isBrowsing = false }
        await network.stop(localPeer)
    }
}
