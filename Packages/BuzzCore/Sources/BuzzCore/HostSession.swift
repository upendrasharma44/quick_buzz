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
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    /// - Parameter flushDelay: pause between sending `end` and tearing down connections, so the
    ///   message reaches players before the link drops.
    public init(
        hostID: PlayerID,
        hostName: String,
        transport: any GameTransport,
        sessionName: String? = nil,
        flushDelay: Duration = .milliseconds(300)
    ) {
        engine = HostEngine(hostID: hostID, hostName: hostName)
        self.sessionName = sessionName ?? Self.defaultSessionName(for: hostName)
        self.transport = transport
        self.flushDelay = flushDelay
    }

    public static func defaultSessionName(for hostName: String) -> String { "\(hostName)'s game" }

    public func start() async {
        guard phase == .idle else { return }
        debugLog(.session, "host start \"\(sessionName)\" as \(engine.host.name) (\(engine.host.id.short)), transport \(type(of: transport)) \(transport.localPeer)")
        phase = .hosting
        listen()
        await advertise()
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
        await transport.stop()
        eventsTask?.cancel()
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
        debugLog(.session, "host ← \(event.logDescription)")
        switch event {
        case .peerConnected(let peer):
            await deliver(engine.peerConnected(peer))
        case .peerDisconnected(let peer):
            await deliver(engine.peerDisconnected(peer))
        case .message(let message, let peer, let receivedAt):
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
