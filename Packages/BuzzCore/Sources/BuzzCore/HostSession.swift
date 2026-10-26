import Foundation
import Observation
import os

/// Runs a game on the host device: pumps transport events into a `HostEngine` and delivers the
/// engine's replies. Views observe `engine` for the roster and round state.
@MainActor
@Observable
public final class HostSession {
    public enum Phase: Hashable, Sendable {
        case idle
        case hosting
        case ended
    }

    public let engine: HostEngine
    public let sessionName: String
    public private(set) var phase: Phase = .idle
    /// Latest non-fatal transport problem, for an inline banner. `nil` when all is well.
    public private(set) var notice: String?

    public var localPeer: PeerID { transport.localPeer }

    @ObservationIgnored private let transport: any GameTransport
    @ObservationIgnored private let flushDelay: Duration
    @ObservationIgnored private let heartbeatInterval: Duration
    @ObservationIgnored private let silenceTimeout: Duration
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    /// When each connected peer last sent anything (pongs included).
    @ObservationIgnored private var lastHeard: [PeerID: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var nextPingID: UInt32 = 0
    @ObservationIgnored private var pingSentAt: [UInt32: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var roundTrips: [PeerID: [Duration]] = [:]

    /// - Parameters:
    ///   - flushDelay: pause between sending `end` and tearing down connections, so the message
    ///     reaches players before the link drops.
    ///   - heartbeatInterval: how often every player is pinged. The steady trickle keeps
    ///     peer-to-peer Wi-Fi links busy and measures round-trip times (debug log).
    ///   - silenceTimeout: a player not heard from for this long is disconnected (it will
    ///     reconnect on its own). Generous on purpose: peer-to-peer Wi-Fi stalls for seconds.
    public init(
        hostID: PlayerID,
        hostName: String,
        transport: any GameTransport,
        sessionName: String? = nil,
        flushDelay: Duration = .milliseconds(300),
        heartbeatInterval: Duration = .seconds(1),
        silenceTimeout: Duration = .seconds(12)
    ) {
        engine = HostEngine(hostID: hostID, hostName: hostName)
        self.sessionName = sessionName ?? Self.defaultSessionName(for: hostName)
        self.transport = transport
        self.flushDelay = flushDelay
        self.heartbeatInterval = heartbeatInterval
        self.silenceTimeout = silenceTimeout
    }

    public static func defaultSessionName(for hostName: String) -> String { "\(hostName)'s game" }

    public func start() async {
        guard phase == .idle else { return }
        debugLog(.session, "host start \"\(sessionName)\" as \(engine.host.name) (\(engine.host.id.short)), transport \(type(of: transport)) \(transport.localPeer)")
        phase = .hosting
        listen()
        await advertise()
        startHeartbeat()
    }

    public func kick(_ playerID: PlayerID) async {
        debugLog(.session, "host kick \(engine.name(of: playerID))")
        await deliver(engine.kick(playerID))
    }

    /// Open the current round for buzzing.
    public func arm() async {
        debugLog(.session, "host arm \(engine.round.id) (\(engine.players.count - 1) players)")
        await deliver(engine.arm())
    }

    /// Clear the round (ranking and lockouts) and wait idle for the next question.
    public func reset() async {
        debugLog(.session, "host reset \(engine.round.id)")
        await deliver(engine.reset())
    }

    /// Clear the round and open the next one straight away.
    public func nextRound() async {
        debugLog(.session, "host next round after \(engine.round.id)")
        await deliver(engine.nextRound())
    }

    /// Add (or, with a negative value, take back) points.
    public func award(points: Int, to playerID: PlayerID) async {
        debugLog(.session, "host award \(points) to \(engine.name(of: playerID))")
        await deliver(engine.award(points: points, to: playerID))
    }

    /// Tell everyone the game is over, then disconnect. Idempotent.
    public func end() async {
        guard phase != .ended else { return }
        let wasHosting = phase == .hosting
        debugLog(.session, "host end (was \(phase))")
        phase = .ended
        if wasHosting {
            await deliver(engine.end())
            try? await Task.sleep(for: flushDelay)
        }
        heartbeatTask?.cancel()
        await transport.stop()
        eventsTask?.cancel()
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self, heartbeatInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)
                guard let self, self.phase == .hosting else { return }
                await self.beat()
            }
        }
    }

    /// Drops players that went silent, then pings everyone else.
    private func beat() async {
        let now = ContinuousClock.now
        let silent = lastHeard.filter { now - $0.value > silenceTimeout }
        for (peer, heard) in silent {
            lastHeard[peer] = nil
            debugLog(.session, "host: \(engine.player(for: peer)?.name ?? "\(peer)") silent for \(now - heard); dropping the link")
            await transport.disconnect(peer)
        }
        guard !lastHeard.isEmpty else { return }
        nextPingID &+= 1
        pingSentAt[nextPingID] = now
        pingSentAt = pingSentAt.filter { nextPingID &- $0.key < 64 }
        do {
            try await transport.broadcast(.ping(id: nextPingID))
        } catch {
            debugLog(.session, "host ping FAILED: \(error)")
        }
    }

    /// Round-trip time of a ping, summarised in the debug log every 10 samples (and on spikes).
    private func recordPong(_ id: UInt32, from peer: PeerID, at receivedAt: ContinuousClock.Instant) {
        guard let sent = pingSentAt[id] else { return }
        let rtt = receivedAt - sent
        let name = engine.player(for: peer)?.name ?? "\(peer)"
        if rtt > .milliseconds(500) { debugLog(.session, "host rtt SPIKE \(name): \(rtt.milliseconds) ms") }
        var samples = roundTrips[peer, default: []]
        samples.append(rtt)
        if samples.count >= 10 {
            let ms = samples.map(\.milliseconds)
            debugLog(.session, "host rtt \(name): min \(ms.min()!) / avg \(ms.reduce(0, +) / ms.count) / max \(ms.max()!) ms over \(ms.count)")
            samples.removeAll()
        }
        roundTrips[peer] = samples
    }

    // MARK: - Private

    private func advertise() async {
        do {
            try await transport.startHosting(sessionName: sessionName)
            notice = nil
        } catch {
            debugLog(.session, "host advertise failed: \(error)")
            notice = error.localizedDescription
        }
    }

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
        if case .message(.pong(let id), let peer, let receivedAt) = event {
            // Heartbeat replies: once a second per player, so kept out of the event log.
            lastHeard[peer] = receivedAt
            recordPong(id, from: peer, at: receivedAt)
            return
        }
        debugLog(.session, "host ← \(event.logDescription)")
        switch event {
        case .peerConnected(let peer):
            lastHeard[peer] = .now
            await deliver(engine.peerConnected(peer))
        case .peerDisconnected(let peer):
            lastHeard[peer] = nil
            roundTrips[peer] = nil
            await deliver(engine.peerDisconnected(peer))
        case .message(let message, let peer, let receivedAt):
            lastHeard[peer] = receivedAt
            if case .buzz(let round) = message {
                debugLog(.session, "host buzz \(round) from \(engine.player(for: peer)?.name ?? "unknown peer \(peer)"), current \(engine.round.id) \(engine.round.phase.rawValue)")
            }
            await deliver(engine.receive(message, from: peer, at: receivedAt))
        case .failed(let error):
            Log.session.error("host transport: \(error.localizedDescription, privacy: .public)")
            notice = error.localizedDescription
        case .hostFound, .hostLost:
            break
        }
    }

    private func deliver(_ outbounds: [Outbound]) async {
        for outbound in outbounds {
            debugLog(.session, "host → \(outbound.logDescription)")
            do {
                try await transport.deliver(outbound)
            } catch {
                // A peer can vanish between the engine's decision and the send; the disconnect
                // event that follows reconciles the roster, so this is not surfaced to the user.
                debugLog(.session, "host send FAILED \(outbound.message.summary): \(error)")
                Log.session.debug("host send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum Log {
    static let session = Logger(subsystem: "com.upendrasharma.buzzlight", category: "session")
}
