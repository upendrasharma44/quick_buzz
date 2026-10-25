import BuzzCore
import Foundation
@preconcurrency import MultipeerConnectivity

/// `GameTransport` over Apple's MultipeerConnectivity. **Legacy**: replaced by `NetworkTransport`
/// (ADR 0007) and kept only for DEBUG A/B device tests. In practice MC needs every phone on the same
/// Wi-Fi network on current iOS; it has not used Bluetooth since iOS 11. Star topology: the host advertises and accepts invitations; players browse and
/// invite the host. See docs/architecture.md and ADRs 0001 and 0004.
///
/// Threading: MultipeerConnectivity calls the delegate methods on its own private queues. All
/// mutable state is guarded by `lock`; events are yielded while holding it so their order matches
/// the order of the callbacks. MultipeerConnectivity APIs are never called with the lock held.
///
/// MultipeerConnectivity behaviours this class works around (verified experimentally):
/// - An invitation sent through a browser that has not (yet) reported that peer is silently
///   dropped — no `.connecting`, no `.notConnected`. Invitations are therefore deferred until the
///   *current* browser finds the peer, and every pending invitation expires on its own.
/// - The framework pauses advertising/browsing in the background and resumes it on its own in the
///   foreground, so `startHosting`/`startBrowsing` never replace a running advertiser/browser.
/// - A session links all of its members to each other, not just to the host, so a player is also
///   connected to the other players. Sessions address players' messages to the host explicitly.
public final class MultipeerTransport: NSObject, GameTransport, @unchecked Sendable {
    /// Must match `NSBonjourServices` in the app's Info.plist (`_buzzlight-mc._tcp` / `_buzzlight-mc._udp`).
    /// Kept apart from `NetworkTransport`'s `_buzzlight._tcp` so the two never discover each other
    /// while both exist for A/B testing (ADR 0007); Multipeer is removed once the switch is verified.
    public static let serviceType = "buzzlight-mc"
    /// The game limit; it also fits an `MCSession` (8 peers including the host).
    public static let maxPlayers = min(SessionLimits.maxPlayers, kMCSessionMaximumNumberOfPeers - 1)
    /// How long a player's invitation waits for the host before MultipeerConnectivity gives up.
    public static let invitationTimeout: TimeInterval = 15
    /// When a pending invitation is declared failed if MultipeerConnectivity never reports back.
    /// Kept below `PlayerSession`'s default 20 s connect timeout.
    static let invitationExpiry: Duration = .seconds(invitationTimeout + 3)

    public let localPeer: PeerID
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let myPeerID: MCPeerID
    private let session: MCSession

    private let lock = NSLock()
    private var registry = PeerRegistry<MCPeerID>()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// Peers the *current* browser has reported and not lost. Invitations only work for these.
    private var found: Set<MCPeerID> = []
    private var connected: Set<MCPeerID> = []
    /// Player side: invitations in flight, keyed to a token so a stale expiry can't cancel a newer attempt.
    private var pendingInvites: [MCPeerID: UUID] = [:]
    /// Player side: invitations waiting for the current browser to find the host.
    private var awaitingDiscovery: Set<MCPeerID> = []
    /// Host side: invitations accepted but not yet connected; they count against `maxPlayers`.
    private var acceptedPending: Set<MCPeerID> = []
    private var stopped = false

    public init(displayName: String) {
        myPeerID = MCPeerID(displayName: PeerName.sanitized(displayName))
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        localPeer = registry.peerID(for: myPeerID, displayName: myPeerID.displayName)
        super.init()
        session.delegate = self
    }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        continuation.finish()
    }

    // MARK: - GameTransport

    public func startHosting(sessionName: String) async throws {
        let created = try lock.withLock { () throws -> MCNearbyServiceAdvertiser? in
            guard !stopped else { throw TransportError.notConnected }
            guard advertiser == nil else { return nil }
            let new = MCNearbyServiceAdvertiser(
                peer: myPeerID,
                discoveryInfo: DiscoveryInfo.make(sessionName: sessionName),
                serviceType: Self.serviceType
            )
            new.delegate = self
            advertiser = new
            return new
        }
        created?.startAdvertisingPeer()
    }

    public func startBrowsing() async throws {
        let created = try lock.withLock { () throws -> MCNearbyServiceBrowser? in
            guard !stopped else { throw TransportError.notConnected }
            guard browser == nil else { return nil }
            let new = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
            new.delegate = self
            browser = new
            found = []
            return new
        }
        created?.startBrowsingForPeers()
    }

    public func stopBrowsing() async {
        let previous = lock.withLock { () -> MCNearbyServiceBrowser? in
            defer { browser = nil; found = [] }
            return browser
        }
        previous?.stopBrowsingForPeers()
    }

    public func connect(to host: PeerID) async throws {
        enum Step { case nothing, invite(MCNearbyServiceBrowser, MCPeerID, UUID), await(MCPeerID, UUID) }
        let step = try lock.withLock { () throws -> Step in
            guard !stopped else { throw TransportError.notConnected }
            guard let browser else { throw TransportError.underlying("connect(to:) requires startBrowsing() first.") }
            guard let mcPeer = registry.key(for: host) else { throw TransportError.peerUnknown(host) }
            if connected.contains(mcPeer) {
                // Keep the contract (success is signalled by `.peerConnected`) even for a link that
                // completed after the caller had given up on it.
                continuation.yield(.peerConnected(host))
                return .nothing
            }
            guard pendingInvites[mcPeer] == nil else { return .nothing }
            let token = UUID()
            pendingInvites[mcPeer] = token
            guard found.contains(mcPeer) else {
                awaitingDiscovery.insert(mcPeer)
                return .await(mcPeer, token)
            }
            return .invite(browser, mcPeer, token)
        }
        switch step {
        case .nothing:
            break
        case .await(let mcPeer, let token):
            scheduleExpiry(of: mcPeer, token: token)
        case .invite(let browser, let mcPeer, let token):
            invite(mcPeer, via: browser, token: token)
        }
    }

    public func send(_ message: GameMessage, to peers: [PeerID]) async throws {
        let targets = try lock.withLock { () throws -> [MCPeerID] in
            try peers.map { peer in
                guard let mcPeer = registry.key(for: peer), connected.contains(mcPeer) else {
                    throw TransportError.peerUnknown(peer)
                }
                return mcPeer
            }
        }
        try transmit(message, to: targets)
    }

    public func broadcast(_ message: GameMessage) async throws {
        let targets = lock.withLock { Array(connected) }
        try transmit(message, to: targets)
    }

    public func stop() async {
        let parts = lock.withLock { () -> (MCNearbyServiceAdvertiser?, MCNearbyServiceBrowser?)? in
            guard !stopped else { return nil }
            stopped = true
            continuation.finish()
            defer {
                advertiser = nil; browser = nil; found = []; connected = []
                pendingInvites = [:]; awaitingDiscovery = []; acceptedPending = []
            }
            return (advertiser, browser)
        }
        guard let (advertiser, browser) = parts else { return }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    // MARK: - Private

    private func invite(_ mcPeer: MCPeerID, via browser: MCNearbyServiceBrowser, token: UUID) {
        debugLog(.transport, "mc invite → \(mcPeer.displayName)")
        browser.invitePeer(mcPeer, to: session, withContext: InvitationContext.current, timeout: Self.invitationTimeout)
        scheduleExpiry(of: mcPeer, token: token)
    }

    /// Declares the invitation failed if MultipeerConnectivity never reports on it.
    private func scheduleExpiry(of mcPeer: MCPeerID, token: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.invitationExpiry)
            self?.expireInvitation(of: mcPeer, token: token)
        }
    }

    private func expireInvitation(of mcPeer: MCPeerID, token: UUID) {
        lock.withLock {
            guard !stopped, pendingInvites[mcPeer] == token else { return }
            pendingInvites[mcPeer] = nil
            awaitingDiscovery.remove(mcPeer)
            let peer = registry.peerID(for: mcPeer, displayName: mcPeer.displayName)
            continuation.yield(.failed(.connectionFailed(peer)))
        }
    }

    private func transmit(_ message: GameMessage, to targets: [MCPeerID]) throws {
        guard !targets.isEmpty else { return }
        let data = try GameMessageCodec.encode(message)
        do {
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            debugLog(.transport, "mc send FAILED \(message.summary): \(error)")
            throw TransportError.underlying(error.localizedDescription)
        }
    }

    /// Mints/looks up the handle for `mcPeer` and yields the event built from it, unless stopped.
    private func emit(for mcPeer: MCPeerID, _ makeEvent: (PeerID) -> TransportEvent?) {
        lock.withLock {
            guard !stopped else { return }
            let peer = registry.peerID(for: mcPeer, displayName: mcPeer.displayName)
            if let event = makeEvent(peer) { continuation.yield(event) }
        }
    }
}

/// Sent with every invitation so a host can turn away a player whose protocol version differs
/// before that player joins the session (and, through MultipeerConnectivity's full mesh, reaches
/// the other players).
enum InvitationContext {
    static var current: Data { Data("v=\(Envelope.currentVersion)".utf8) }

    static func isCompatible(_ context: Data?) -> Bool {
        context == current
    }
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        debugLog(.transport, "mc \(peerID.displayName) state \(state.rawValue) (0 notConnected, 1 connecting, 2 connected)")
        emit(for: peerID) { peer in
            switch state {
            case .connected:
                pendingInvites[peerID] = nil
                acceptedPending.remove(peerID)
                return connected.insert(peerID).inserted ? .peerConnected(peer) : nil
            case .notConnected:
                acceptedPending.remove(peerID)
                if connected.remove(peerID) != nil { return .peerDisconnected(peer) }
                if pendingInvites.removeValue(forKey: peerID) != nil { return .failed(.connectionFailed(peer)) }
                return nil
            case .connecting:
                return nil
            @unknown default:
                return nil
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let receivedAt = ContinuousClock.now
        enum Decoded { case message(GameMessage), incompatible(Int), unreadable }
        let decoded: Decoded
        do {
            decoded = .message(try GameMessageCodec.decode(data))
        } catch ProtocolError.unsupportedVersion(let version) {
            decoded = .incompatible(version)
        } catch {
            decoded = .unreadable
        }
        emit(for: peerID) { peer in
            switch decoded {
            case .message(let message): .message(message, from: peer, receivedAt: receivedAt)
            case .incompatible(let version): .failed(.incompatibleVersion(version, from: peer))
            case .unreadable: .failed(.underlying("Unreadable message from \(peerID.displayName)."))
            }
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    public func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    /// v1 auto-accepts compatible players until the session is full (host approval is Stage 4).
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        defer { debugLog(.transport, "mc invitation from \(peerID.displayName)") }
        let accept = lock.withLock { () -> Bool in
            guard !stopped, InvitationContext.isCompatible(context) else { return false }
            if connected.contains(peerID) || acceptedPending.contains(peerID) { return true }
            guard connected.count + acceptedPending.count < Self.maxPlayers else { return false }
            acceptedPending.insert(peerID)
            return true
        }
        invitationHandler(accept, accept ? session : nil)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        lock.withLock {
            guard !stopped, advertiser === self.advertiser else { return }
            continuation.yield(.failed(.underlying("Couldn't start hosting: \(error.localizedDescription)")))
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let deferred = lock.withLock { () -> UUID? in
            guard !stopped, browser === self.browser else { return nil }
            found.insert(peerID)
            let peer = registry.peerID(for: peerID, displayName: peerID.displayName)
            continuation.yield(.hostFound(DiscoveredHost(
                id: peer,
                sessionName: DiscoveryInfo.sessionName(from: info, fallback: peerID.displayName),
                isCompatible: DiscoveryInfo.isCompatible(info)
            )))
            guard awaitingDiscovery.remove(peerID) != nil else { return nil }
            let token = UUID()
            pendingInvites[peerID] = token
            return token
        }
        if let token = deferred { invite(peerID, via: browser, token: token) }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.withLock {
            guard !stopped, browser === self.browser else { return }
            found.remove(peerID)
            continuation.yield(.hostLost(registry.peerID(for: peerID, displayName: peerID.displayName)))
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        lock.withLock {
            guard !stopped, browser === self.browser else { return }
            continuation.yield(.failed(.underlying("Couldn't look for games: \(error.localizedDescription)")))
        }
    }
}
