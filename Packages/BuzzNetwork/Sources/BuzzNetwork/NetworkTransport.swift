import BuzzCore
import Foundation
import Network

/// `GameTransport` over Network.framework (ADR 0007): the host runs an `NWListener` advertised over
/// Bonjour, players find it with an `NWBrowser` and open one `NWConnection` each. Peer-to-peer
/// Wi-Fi is enabled, so phones that have Wi-Fi switched on can play without sharing a network.
/// Frames are `GameMessageCodec` envelopes in binary WebSocket messages over TLS-PSK.
///
/// Threading: Network.framework calls back on `queue`, while the `GameTransport` methods are called
/// from any task. All mutable state is guarded by `lock`; events are yielded while holding it so
/// their order matches the callbacks. Network.framework is never called with the lock held.
public final class NetworkTransport: GameTransport, @unchecked Sendable {
    /// Bonjour service type; must be listed in Info.plist `NSBonjourServices`.
    public static let serviceType = "_buzzlight._tcp"
    public static let maxPlayers = SessionLimits.maxPlayers
    /// A connection that is not ready by then is abandoned with `.connectionFailed`.
    /// Kept below `PlayerSession`'s default 20 s connect timeout.
    static let connectionExpiry: Duration = .seconds(18)

    public let localPeer: PeerID
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let queue = DispatchQueue(label: "com.upendrasharma.buzzlight.network")
    private let lock = NSLock()

    /// Hosts are keyed by their Bonjour endpoint (stable across browser restarts, so a player can
    /// reconnect to the same `PeerID`); incoming connections on the host by a per-connection UUID.
    private enum Key: Hashable {
        case endpoint(NWEndpoint)
        case incoming(UUID)
    }

    private var registry = PeerRegistry<Key>()
    private var listener: NWListener?
    private var browser: NWBrowser?
    /// Every live connection, ready or not.
    private var connections: [PeerID: NWConnection] = [:]
    private var ready: Set<PeerID> = []
    /// Connection attempts not yet ready, with a token so a stale expiry can't cancel a newer one.
    private var pending: [PeerID: UUID] = [:]
    private var stopped = false

    public init(displayName: String) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        localPeer = PeerID(rawValue: "\(PeerName.sanitized(displayName))#local")
    }

    deinit {
        listener?.cancel()
        browser?.cancel()
        for connection in connections.values { connection.cancel() }
        continuation.finish()
    }

    // MARK: - GameTransport: host

    public func startHosting(sessionName: String) async throws {
        let created = try lock.withLock { () throws -> NWListener? in
            guard !stopped else { throw TransportError.notConnected }
            guard listener == nil else { return nil }
            let new: NWListener
            do {
                new = try NWListener(using: NetworkParameters.make())
            } catch {
                throw TransportError.underlying("Couldn't start hosting: \(error.localizedDescription)")
            }
            new.service = NWListener.Service(
                name: PeerName.truncated(sessionName, maxBytes: PeerName.maxDisplayNameBytes),
                type: Self.serviceType,
                txtRecord: NWTXTRecord(DiscoveryInfo.make(sessionName: sessionName))
            )
            listener = new
            return new
        }
        guard let created else { return }
        created.stateUpdateHandler = { [weak self, weak created] state in
            debugLog(.transport, "listener state \(state)\(state == .ready ? " port \(created?.port.map(String.init(describing:)) ?? "?")" : "")")
            guard let self, let created, case .failed(let error) = state else { return }
            self.yieldIfCurrent(listener: created, .failed(.underlying("Couldn't start hosting: \(error.localizedDescription)")))
        }
        created.serviceRegistrationUpdateHandler = { change in
            debugLog(.transport, "listener bonjour \(change)")
        }
        created.newConnectionHandler = { [weak self] connection in
            debugLog(.transport, "listener incoming connection from \(connection.endpoint)")
            self?.accept(connection)
        }
        created.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        let admitted = lock.withLock { () -> (PeerID, UUID)? in
            // Pending handshakes count against the limit too, so simultaneous joins can't overfill.
            guard !stopped, connections.count < Self.maxPlayers else { return nil }
            let peer = registry.peerID(for: .incoming(UUID()), displayName: "player")
            let token = UUID()
            connections[peer] = connection
            pending[peer] = token
            return (peer, token)
        }
        guard let (peer, token) = admitted else {
            // Full or stopped. Start then close, so the player hears "no" at once instead of
            // waiting out its connection expiry on a socket nobody will ever answer.
            debugLog(.transport, "incoming connection REFUSED (full or stopped) from \(connection.endpoint)")
            connection.start(queue: queue)
            connection.cancel()
            return
        }
        start(connection, as: peer)
        scheduleExpiry(of: peer, token: token)  // frees the slot if the handshake never completes
    }

    // MARK: - GameTransport: player

    public func startBrowsing() async throws {
        let created = try lock.withLock { () throws -> NWBrowser? in
            guard !stopped else { throw TransportError.notConnected }
            guard browser == nil else { return nil }
            let new = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
                                using: NetworkParameters.make())
            browser = new
            return new
        }
        guard let created else { return }
        created.browseResultsChangedHandler = { [weak self, weak created] _, changes in
            for change in changes { debugLog(.transport, "browse \(Self.describe(change))") }
            guard let self, let created else { return }
            self.handle(changes, from: created)
        }
        created.stateUpdateHandler = { [weak self, weak created] state in
            debugLog(.transport, "browser state \(state)")
            guard let self, let created, case .failed(let error) = state else { return }
            self.yieldIfCurrent(browser: created, .failed(.underlying("Couldn't look for games: \(error.localizedDescription)")))
        }
        created.start(queue: queue)
    }

    /// Stops browsing, **unless** a connection runs over peer-to-peer Wi-Fi. On a phone whose only
    /// route to the host is AWDL, iOS tears the link down a couple of seconds after the last browse
    /// stops: device logs (2026-10-25) showed every such connection dying 2–3 s after joining and
    /// recovering the moment browsing restarted. Over infrastructure Wi-Fi the browser is stopped,
    /// since an active browse makes the radio hop to AWDL channels and adds jitter.
    public func stopBrowsing() async {
        let (previous, peerToPeer) = lock.withLock { () -> (NWBrowser?, [String]) in
            let interfaces = connections.values.flatMap { connection in
                (connection.currentPath?.availableInterfaces ?? []).map(\.name)
            }
            guard !Self.needsBrowsingToStayUp(interfaceNames: interfaces) else { return (nil, interfaces) }
            defer { browser = nil }
            return (browser, interfaces)
        }
        if previous == nil, Self.needsBrowsingToStayUp(interfaceNames: peerToPeer) {
            debugLog(.transport, "keeping the browser running: connected over peer-to-peer Wi-Fi \(peerToPeer)")
        }
        previous?.cancel()
    }

    /// True when any of the interfaces is peer-to-peer Wi-Fi (`awdl*`, or `llw*` low-latency WLAN).
    static func needsBrowsingToStayUp(interfaceNames: [String]) -> Bool {
        interfaceNames.contains { $0.hasPrefix("awdl") || $0.hasPrefix("llw") }
    }

    public func connect(to host: PeerID) async throws {
        let attempt = try lock.withLock { () throws -> (NWConnection, UUID)? in
            guard !stopped else { throw TransportError.notConnected }
            guard case .endpoint(let endpoint)? = registry.key(for: host) else { throw TransportError.peerUnknown(host) }
            if ready.contains(host) {
                // Keep the contract: success is signalled by `.peerConnected`, even for a link
                // that completed after the caller had given up on it.
                continuation.yield(.peerConnected(host))
                return nil
            }
            guard connections[host] == nil else { return nil }  // attempt already in flight
            let connection = NWConnection(to: endpoint, using: NetworkParameters.make())
            let token = UUID()
            connections[host] = connection
            pending[host] = token
            return (connection, token)
        }
        guard let (connection, token) = attempt else { return }
        start(connection, as: host)
        scheduleExpiry(of: host, token: token)
    }

    // MARK: - GameTransport: both

    public func send(_ message: GameMessage, to peers: [PeerID]) async throws {
        let targets = try lock.withLock { () throws -> [NWConnection] in
            try peers.map { peer in
                guard ready.contains(peer), let connection = connections[peer] else { throw TransportError.peerUnknown(peer) }
                return connection
            }
        }
        try transmit(GameMessageCodec.encode(message), to: targets)
    }

    public func broadcast(_ message: GameMessage) async throws {
        let targets = lock.withLock { ready.compactMap { connections[$0] } }
        try transmit(GameMessageCodec.encode(message), to: targets)
    }

    public func stop() async {
        let parts = lock.withLock { () -> (NWListener?, NWBrowser?, [NWConnection])? in
            guard !stopped else { return nil }
            stopped = true
            continuation.finish()
            defer { listener = nil; browser = nil; connections = [:]; ready = []; pending = [:] }
            return (listener, browser, Array(connections.values))
        }
        guard let (listener, browser, connections) = parts else { return }
        listener?.cancel()
        browser?.cancel()
        for connection in connections { connection.cancel() }
    }

    // MARK: - Test hooks

    /// Sends raw bytes as one frame (tests: frames from other protocol versions).
    func sendRaw(_ data: Data, to peer: PeerID) throws {
        let target = try lock.withLock { () throws -> NWConnection in
            guard ready.contains(peer), let connection = connections[peer] else { throw TransportError.peerUnknown(peer) }
            return connection
        }
        transmit(data, to: [target])
    }

    public func disconnect(_ peer: PeerID) async {
        let connection = lock.withLock { connections[peer] }
        debugLog(.transport, "conn \(peer) disconnect requested\(connection == nil ? " (no such connection)" : "")")
        connection?.cancel()
    }

    // MARK: - Connections

    private func start(_ connection: NWConnection, as peer: PeerID) {
        connection.viabilityUpdateHandler = { [weak connection] viable in
            debugLog(.transport, "conn \(peer) viable=\(viable)\(connection.map { " path " + Self.describe($0.currentPath) } ?? "")")
        }
        connection.betterPathUpdateHandler = { better in
            debugLog(.transport, "conn \(peer) betterPathAvailable=\(better)")
        }
        connection.pathUpdateHandler = { path in
            debugLog(.transport, "conn \(peer) path \(Self.describe(path))")
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            debugLog(.transport, "conn \(peer) state \(state)\(state == .ready ? " via " + Self.describe(connection?.currentPath) : "")")
            guard let self, let connection else { return }
            self.handle(state, of: connection, as: peer)
        }
        connection.start(queue: queue)
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection, as peer: PeerID) {
        switch state {
        case .ready:
            let isNew = lock.withLock { () -> Bool in
                guard !stopped, connections[peer] === connection else { return false }
                pending[peer] = nil
                guard ready.insert(peer).inserted else { return false }
                continuation.yield(.peerConnected(peer))
                return true
            }
            if isNew { receive(on: connection, from: peer) }
        case .failed, .cancelled:
            let wasCurrent = lock.withLock { () -> Bool in
                guard !stopped, connections[peer] === connection else { return false }
                connections[peer] = nil
                let wasPending = pending.removeValue(forKey: peer) != nil
                if ready.remove(peer) != nil {
                    continuation.yield(.peerDisconnected(peer))
                } else if wasPending, case .endpoint? = registry.key(for: peer) {
                    continuation.yield(.failed(.connectionFailed(peer)))
                }
                // Incoming connections never come back under the same handle.
                if case .incoming? = registry.key(for: peer) { registry.remove(peer) }
                return true
            }
            if wasCurrent, case .failed = state { connection.cancel() }
        case .waiting, .preparing, .setup:
            // `.waiting` (no route right now) is not fatal: Network.framework retries, and the
            // pending expiry gives up on attempts that never become ready.
            break
        @unknown default:
            break
        }
    }

    private func receive(on connection: NWConnection, from peer: PeerID) {
        connection.receiveMessage { [weak self, weak connection] content, context, _, error in
            let receivedAt = ContinuousClock.now
            if let error { debugLog(.transport, "conn \(peer) receive error \(error)") }
            guard let self, let connection else { return }
            if let content, !content.isEmpty {
                self.deliver(content, from: peer, via: connection, receivedAt: receivedAt)
            }
            // On error the state handler reports `.failed` and cleans up.
            guard error == nil else { return }
            // The other side closed (WebSocket close frame or end of stream). Without this check
            // `receiveMessage` keeps completing with no data and the loop spins until keepalive
            // gives up seconds later; cancelling reports `.peerDisconnected` right away.
            let webSocket = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if webSocket?.opcode == .close || context?.isFinal == true {
                debugLog(.transport, "conn \(peer) closed by other side (\(webSocket?.opcode == .close ? "close frame" : "end of stream")); cancelling")
                connection.cancel()
                return
            }
            self.receive(on: connection, from: peer)
        }
    }

    private func deliver(_ data: Data, from peer: PeerID, via connection: NWConnection, receivedAt: ContinuousClock.Instant) {
        let event: TransportEvent
        var reject = false
        do {
            event = .message(try GameMessageCodec.decode(data), from: peer, receivedAt: receivedAt)
        } catch ProtocolError.unsupportedVersion(let version) {
            event = .failed(.incompatibleVersion(version, from: peer))
            reject = true
            debugLog(.transport, "conn \(peer) frame from protocol v\(version); turning away")
        } catch {
            debugLog(.transport, "conn \(peer) unreadable frame (\(data.count) bytes): \(error)")
            event = .failed(.underlying("Unreadable message from \(peer)."))
        }
        let current = lock.withLock { () -> Bool in
            guard !stopped, connections[peer] === connection else { return false }
            continuation.yield(event)
            return true
        }
        // A phone speaking another protocol version is turned away rather than kept in the game.
        if current, reject, case .incoming? = lock.withLock({ registry.key(for: peer) }) {
            connection.cancel()
        }
    }

    private func transmit(_ data: Data, to targets: [NWConnection]) {
        for connection in targets {
            let started = ContinuousClock.now
            connection.send(content: data, contentContext: NetworkParameters.frameContext,
                            isComplete: true, completion: .contentProcessed { error in
                if let error {
                    debugLog(.transport, "send FAILED \(data.count) bytes to \(connection.endpoint): \(error)")
                } else {
                    let elapsed = ContinuousClock.now - started
                    if elapsed > .milliseconds(200) {  // a slow link shows up here before it drops
                        debugLog(.transport, "send slow: \(data.count) bytes to \(connection.endpoint) took \(elapsed)")
                    }
                }
            })
        }
    }

    /// Gives up on an attempt that never became ready.
    private func scheduleExpiry(of peer: PeerID, token: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.connectionExpiry)
            guard let self else { return }
            let expired = self.lock.withLock { () -> NWConnection? in
                guard !self.stopped, self.pending[peer] == token else { return nil }
                self.pending[peer] = nil
                let connection = self.connections.removeValue(forKey: peer)
                switch self.registry.key(for: peer) {
                case .endpoint?:
                    debugLog(.transport, "conn \(peer) not ready after \(Self.connectionExpiry); giving up")
                    self.continuation.yield(.failed(.connectionFailed(peer)))  // the player's join failed
                case .incoming?:
                    debugLog(.transport, "incoming \(peer) handshake never completed; freeing slot")
                    self.registry.remove(peer)  // a half-open incoming handshake: just free the slot
                case nil:
                    break
                }
                return connection
            }
            expired?.cancel()
        }
    }

    // MARK: - Browsing

    private func handle(_ changes: Set<NWBrowser.Result.Change>, from source: NWBrowser) {
        lock.withLock {
            guard !stopped, source === browser else { return }
            for change in changes {
                switch change {
                case .added(let result), .changed(_, let result, _):
                    continuation.yield(.hostFound(host(for: result)))
                case .removed(let result):
                    continuation.yield(.hostLost(registry.peerID(for: .endpoint(result.endpoint), displayName: Self.serviceName(of: result))))
                case .identical:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    /// Must be called with `lock` held (mints a `PeerID`).
    private func host(for result: NWBrowser.Result) -> DiscoveredHost {
        let txt: [String: String]?
        if case .bonjour(let record) = result.metadata { txt = record.dictionary } else { txt = nil }
        let name = Self.serviceName(of: result)
        return DiscoveredHost(
            id: registry.peerID(for: .endpoint(result.endpoint), displayName: name),
            sessionName: DiscoveryInfo.sessionName(from: txt, fallback: name),
            isCompatible: DiscoveryInfo.isCompatible(txt)
        )
    }

    static func describe(_ path: NWPath?) -> String {
        guard let path else { return "(no path)" }
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        return "\(path.status) [\(interfaces)]\(path.isExpensive ? " expensive" : "")\(path.isConstrained ? " constrained" : "")"
    }

    static func describe(_ change: NWBrowser.Result.Change) -> String {
        func one(_ r: NWBrowser.Result) -> String {
            "\(r.endpoint) interfaces [\(r.interfaces.map { "\($0.name):\($0.type)" }.joined(separator: ","))]"
        }
        switch change {
        case .added(let r): return "added \(one(r))"
        case .removed(let r): return "removed \(one(r))"
        case .changed(_, let r, let flags): return "changed \(one(r)) flags \(flags)"
        case .identical: return "identical"
        @unknown default: return "unknown change"
        }
    }

    private static func serviceName(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "Game"
    }

    private func yieldIfCurrent(listener source: NWListener, _ event: TransportEvent) {
        lock.withLock { if !stopped, source === listener { continuation.yield(event) } }
    }

    private func yieldIfCurrent(browser source: NWBrowser, _ event: TransportEvent) {
        lock.withLock { if !stopped, source === browser { continuation.yield(event) } }
    }
}
