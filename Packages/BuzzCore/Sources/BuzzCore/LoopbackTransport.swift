import Foundation

/// In-process "network" shared by several `LoopbackTransport`s. Lets tests, SwiftUI previews and
/// the app's demo mode run a host and players in one process with real message passing but no sockets.
public actor LoopbackNetwork {
    private var transports: [PeerID: LoopbackTransport] = [:]
    private var hosts: [PeerID: String] = [:]
    private var links: Set<Link> = []
    private var minted = 0

    private struct Link: Hashable { let a: PeerID; let b: PeerID
        init(_ x: PeerID, _ y: PeerID) { (a, b) = x.rawValue < y.rawValue ? (x, y) : (y, x) }
        func contains(_ p: PeerID) -> Bool { a == p || b == p }
        func other(than p: PeerID) -> PeerID { a == p ? b : a }
    }

    public init() {}

    /// Creates a transport whose `localPeer` is unique on this network even if `name` repeats.
    public func makeTransport(name: String) -> LoopbackTransport {
        minted += 1
        let t = LoopbackTransport(localPeer: PeerID(rawValue: "\(name)#\(minted)"), network: self)
        transports[t.localPeer] = t
        return t
    }

    /// Simulates a transient drop (e.g. the app was backgrounded): both ends see `.peerDisconnected`
    /// but stay alive, and a host keeps advertising, so the player can reconnect.
    public func dropLink(between a: PeerID, and b: PeerID) {
        guard links.remove(Link(a, b)) != nil else { return }
        transports[a]?.emit(.peerDisconnected(b))
        transports[b]?.emit(.peerDisconnected(a))
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
        guard links.insert(Link(from, host)).inserted else {
            f.emit(.peerConnected(host))  // already linked: re-confirm, as the contract requires
            return
        }
        h.emit(.peerConnected(from))
        f.emit(.peerConnected(host))
    }

    fileprivate func send(_ message: GameMessage, from: PeerID, to peers: [PeerID]) throws {
        for p in peers {
            guard links.contains(Link(from, p)), let t = transports[p] else { throw TransportError.peerUnknown(p) }
            t.emit(.message(message, from: from, receivedAt: .now))
        }
    }

    fileprivate func broadcast(_ message: GameMessage, from: PeerID) {
        for link in links where link.contains(from) {
            transports[link.other(than: from)]?.emit(.message(message, from: from, receivedAt: .now))
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
        transports.removeValue(forKey: peer)
    }
}

public final class LoopbackTransport: GameTransport, @unchecked Sendable {
    public let localPeer: PeerID
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let network: LoopbackNetwork
    private let lock = NSLock()
    private var _isBrowsing = false
    private var _isStopped = false

    fileprivate var isBrowsing: Bool { lock.withLock { _isBrowsing } }

    fileprivate init(localPeer: PeerID, network: LoopbackNetwork) {
        self.localPeer = localPeer
        self.network = network
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    fileprivate func emit(_ event: TransportEvent) {
        lock.withLock { if !_isStopped { continuation.yield(event) } }
    }

    public func startHosting(sessionName: String) async throws {
        await network.advertise(localPeer, sessionName: sessionName)
    }

    public func startBrowsing() async throws {
        let wasBrowsing = lock.withLock {
            defer { _isBrowsing = true }
            return _isBrowsing
        }
        guard !wasBrowsing else { return }
        await network.browse(localPeer)
    }

    public func stopBrowsing() async {
        lock.withLock { _isBrowsing = false }
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
        let first = lock.withLock {
            defer { _isStopped = true; _isBrowsing = false }
            return !_isStopped
        }
        guard first else { return }
        continuation.finish()
        await network.stop(localPeer)
    }
}
