import Foundation
import Observation

/// Runs the player side: discovers hosts, joins one, keeps the connection alive across short
/// drops (backgrounding, Wi-Fi blips) and pumps host messages into a `PlayerEngine`.
@MainActor
@Observable
public final class PlayerSession {
    public enum Phase: Hashable, Sendable {
        case idle
        /// Looking for hosts; `hosts` is live.
        case browsing
        /// Invitation sent to the host; waiting for the connection.
        case connecting(DiscoveredHost)
        /// Connected. `engine.status` says what the screen should show.
        case joined(DiscoveredHost)
        /// The link to the host dropped unexpectedly; retrying until `reconnectTimeout`.
        case reconnecting(DiscoveredHost)
        case ended(EndReason)
    }

    public enum EndReason: Hashable, Sendable {
        case left
        case hostEnded
        case kicked
        case connectionLost
        case incompatibleVersion
    }

    public let engine: PlayerEngine
    public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { debugLog(.session, "player phase \(oldValue) → \(phase)") } }
    }
    /// Hosts currently visible, sorted by session name.
    public private(set) var hosts: [DiscoveredHost] = []
    /// Non-fatal problem to show inline (e.g. a failed join). Cleared by the next join attempt.
    public private(set) var notice: String? {
        didSet { if let notice, notice != oldValue { debugLog(.session, "player notice: \(notice)") } }
    }

    @ObservationIgnored private let transport: any GameTransport
    @ObservationIgnored private let connectTimeout: Duration
    @ObservationIgnored private let reconnectTimeout: Duration
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isBackgrounded = false

    /// - Parameters:
    ///   - connectTimeout: give up on a join attempt after this long. Keep it above the
    ///     transport's own invitation timeout so the transport normally reports failure first.
    ///   - reconnectTimeout: how long to keep retrying after an unexpected drop, counted only
    ///     while the app is in the foreground.
    ///   - retryDelay: pause before re-inviting the host after a failed reconnect attempt.
    public init(
        playerID: PlayerID,
        name: String,
        transport: any GameTransport,
        connectTimeout: Duration = .seconds(20),
        reconnectTimeout: Duration = .seconds(30),
        retryDelay: Duration = .seconds(1)
    ) {
        engine = PlayerEngine(id: playerID, name: name)
        self.transport = transport
        self.connectTimeout = connectTimeout
        self.reconnectTimeout = reconnectTimeout
        self.retryDelay = retryDelay
    }

    public var localPeer: PeerID { transport.localPeer }

    public var host: DiscoveredHost? {
        switch phase {
        case .connecting(let h), .joined(let h), .reconnecting(let h): h
        case .idle, .browsing, .ended: nil
        }
    }

    // MARK: - Actions

    public func start() async {
        guard phase == .idle else { return }
        debugLog(.session, "player start as \(engine.me.name) (\(engine.me.id.short)), transport \(type(of: transport)) \(transport.localPeer)")
        phase = .browsing
        listen()
        await browse()
    }

    public func join(_ host: DiscoveredHost) async {
        guard phase == .browsing else { return }
        debugLog(.session, "player join \(host.id) \"\(host.sessionName)\"")
        guard host.isCompatible else {
            notice = "\(host.sessionName) uses a different version of BuzzLight. Update both phones and try again."
            return
        }
        notice = nil
        phase = .connecting(host)
        armTimeout(connectTimeout) { $0.connectTimedOut(host) }
        do {
            try await transport.connect(to: host.id)
        } catch {
            joinFailed(host, error)
        }
    }

    public func leave() async {
        debugLog(.session, "player leave")
        await finish(.left)
    }

    /// Press the buzzer. Deliberately synchronous: the engine registers the press in the same
    /// main-actor turn as the touch-down that triggered it, and only the send is deferred. Keep it
    /// that way (ADR 0005 will stamp the press here).
    public func buzz() {
        guard case .joined = phase else {
            debugLog(.session, "player buzz IGNORED: phase \(phase)")
            return
        }
        let before = engine.status
        let outbounds = engine.buzz()
        debugLog(.session, "player buzz pressed: status \(before) → \(engine.status), round \(engine.round.map { "\($0.id) \($0.phase.rawValue)" } ?? "none"), \(outbounds.isEmpty ? "nothing sent" : "sending")")
        guard !outbounds.isEmpty else { return }
        Task { await deliver(outbounds) }
    }

    /// Call when the scene moves to the background. The system drops the connection there, and the
    /// reconnect deadline must not run down while the app is suspended.
    public func sceneDidEnterBackground() {
        debugLog(.session, "player scene → background (phase \(phase))")
        isBackgrounded = true
        if case .reconnecting = phase { cancelTimeout() }
    }

    /// Call when the scene is active again: give the reconnect a fresh deadline and retry now.
    /// (Browsing itself resumes on its own; the transport handles that.)
    public func sceneDidBecomeActive() async {
        debugLog(.session, "player scene → active (phase \(phase))")
        isBackgrounded = false
        guard case .reconnecting(let target) = phase else { return }
        armReconnectTimeout()
        await browse()
        try? await transport.connect(to: target.id)
    }

    // MARK: - Events

    private func listen() {
        let events = transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: TransportEvent) async {
        debugLog(.session, "player ← \(event.logDescription)")
        switch event {
        case .hostFound(let found):
            hosts.removeAll { $0.id == found.id }
            hosts.append(found)
            hosts.sort { $0.sessionName.localizedStandardCompare($1.sessionName) == .orderedAscending }
            if case .reconnecting(let target) = phase, target.id == found.id {
                try? await transport.connect(to: target.id)
            }

        case .hostLost(let peer):
            hosts.removeAll { $0.id == peer }

        case .peerConnected(let peer):
            guard let target = host, target.id == peer else { return }
            switch phase {
            case .connecting, .reconnecting:
                cancelTimeout()
                phase = .joined(target)
                await transport.stopBrowsing()
                await deliver(engine.connected())
            default:
                break
            }

        case .peerDisconnected(let peer):
            guard case .joined(let target) = phase, target.id == peer else { return }
            phase = .reconnecting(target)
            hosts = []  // browsing starts over; entries from before the drop may be stale
            if !isBackgrounded { armReconnectTimeout() }
            await browse()
            // The transport holds this until the host is found again.
            try? await transport.connect(to: target.id)

        case .message(let message, let peer, _):
            guard case .joined(let target) = phase, target.id == peer else { return }
            await deliver(engine.receive(message))
            switch engine.status {
            case .kicked: await finish(.kicked)
            case .ended: await finish(.hostEnded)
            default: break
            }

        case .failed(.incompatibleVersion(_, let peer)):
            // Other players share the session mesh; only the host's version matters.
            if host?.id == peer { await finish(.incompatibleVersion) }

        case .failed(.connectionFailed(let peer)):
            switch phase {
            case .connecting(let target) where target.id == peer:
                joinFailed(target, TransportError.connectionFailed(peer))
            case .reconnecting(let target) where target.id == peer:
                scheduleRetry(target)
            default:
                break
            }

        case .failed(let error):
            notice = error.localizedDescription
        }
    }

    // MARK: - Private

    private func browse() async {
        do {
            try await transport.startBrowsing()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func joinFailed(_ target: DiscoveredHost, _ error: any Error) {
        guard phase == .connecting(target) else { return }
        cancelTimeout()
        phase = .browsing
        notice = "Couldn't join \(target.sessionName). \(error.localizedDescription)"
    }

    private func connectTimedOut(_ target: DiscoveredHost) {
        debugLog(.session, "player connect timeout for \(target.id)")
        joinFailed(target, TransportError.connectionFailed(target.id))
    }

    private func scheduleRetry(_ target: DiscoveredHost) {
        Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard let self, self.phase == .reconnecting(target) else { return }
            debugLog(.session, "player reconnect retry → \(target.id)")
            try? await self.transport.connect(to: target.id)
        }
    }

    private func finish(_ reason: EndReason) async {
        if case .ended = phase { return }
        cancelTimeout()
        if reason == .connectionLost { engine.disconnected() }
        phase = .ended(reason)
        await transport.stop()
        eventsTask?.cancel()
    }

    private func armReconnectTimeout() {
        debugLog(.session, "player reconnect deadline armed (\(reconnectTimeout))")
        armTimeout(reconnectTimeout) {
            debugLog(.session, "player reconnect deadline EXPIRED")
            await $0.finish(.connectionLost)
        }
    }

    private func armTimeout(_ duration: Duration, _ action: @escaping @MainActor (PlayerSession) async -> Void) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            await action(self)
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Players only ever talk to the host. Recipients are ignored on purpose: MultipeerConnectivity
    /// links every member of a session, so a "broadcast" would also reach the other players.
    private func deliver(_ outbounds: [Outbound]) async {
        guard let target = host else {
            debugLog(.session, "player send DROPPED (no host, phase \(phase)): \(outbounds.map(\.message.summary))")
            return
        }
        for outbound in outbounds {
            debugLog(.session, "player → \(outbound.message.summary) → \(target.id)")
            do {
                try await transport.send(outbound.message, to: [target.id])
            } catch {
                debugLog(.session, "player send FAILED \(outbound.message.summary): \(error)")
                Log.session.debug("player send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension PlayerSession.Phase: CustomStringConvertible {
    /// Compact form for the debug log, e.g. `connecting(Hana's game#1)`.
    public var description: String {
        switch self {
        case .idle: "idle"
        case .browsing: "browsing"
        case .connecting(let host): "connecting(\(host.id))"
        case .joined(let host): "joined(\(host.id))"
        case .reconnecting(let host): "reconnecting(\(host.id))"
        case .ended(let reason): "ended(\(reason))"
        }
    }
}
