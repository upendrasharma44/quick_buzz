import Foundation
import Observation

/// Authoritative game state, run on the host device.
///
/// The engine is deliberately synchronous and transport-agnostic: every input returns the
/// messages that must be sent as a result, and the caller (a session object or a test) decides
/// how to deliver them. Arrival order of `buzz` messages at the host is the sole arbiter of
/// ranking; device clocks are never consulted.
@MainActor
@Observable
public final class HostEngine {
    public private(set) var players: [Player]
    public private(set) var round: RoundState
    public private(set) var scores: [PlayerID: Int] = [:]
    public private(set) var isEnded = false

    public let host: Player
    /// Everyone who has been in this session, including players who have since left. Never shrinks,
    /// so rankings and scores stay readable after someone disconnects.
    public private(set) var knownNames: [PlayerID: String]
    private var peerToPlayer: [PeerID: PlayerID] = [:]
    private var playerToPeer: [PlayerID: PeerID] = [:]
    private var firstBuzzAt: ContinuousClock.Instant?

    public init(hostID: PlayerID, hostName: String) {
        host = Player(id: hostID, name: hostName, isHost: true)
        players = [host]
        knownNames = [hostID: hostName]
        round = RoundState(id: RoundID(1))
    }

    public var snapshot: SessionSnapshot {
        SessionSnapshot(players: players, round: round, scores: scores, names: knownNames)
    }

    public func player(for peer: PeerID) -> Player? {
        guard let id = peerToPlayer[peer] else { return nil }
        return players.first { $0.id == id }
    }

    public func name(of playerID: PlayerID) -> String {
        players.first { $0.id == playerID }?.name ?? knownNames[playerID] ?? "?"
    }

    /// `true` while the player is connected (they may have scores after leaving).
    public func isPresent(_ playerID: PlayerID) -> Bool {
        players.contains { $0.id == playerID }
    }

    // MARK: - Transport events

    /// A device connected. Nothing happens until it sends `hello`.
    public func peerConnected(_ peer: PeerID) -> [Outbound] { [] }

    public func peerDisconnected(_ peer: PeerID) -> [Outbound] {
        guard let playerID = peerToPlayer.removeValue(forKey: peer) else { return [] }
        playerToPeer.removeValue(forKey: playerID)
        players.removeAll { $0.id == playerID }
        return [.all(.roster(players: players))]
    }

    public func receive(_ message: GameMessage, from peer: PeerID, at now: ContinuousClock.Instant = .now) -> [Outbound] {
        guard !isEnded else { return [] }
        switch message {
        case .hello(let playerID, let name):
            return handleHello(playerID: playerID, name: name, from: peer)
        case .buzz(let roundID):
            return handleBuzz(round: roundID, from: peer, at: now)
        case .ping(let id):
            return [.peer(peer, .pong(id: id))]
        default:
            // Host-originated messages echoed back, or pong (handled by the RTT layer in Stage 4).
            return []
        }
    }

    // MARK: - Host actions

    /// Open the current round for buzzing. No-op unless the round is idle.
    public func arm() -> [Outbound] {
        guard !isEnded, round.phase == .idle else { return [] }
        round.phase = .armed
        round.ranking = []
        firstBuzzAt = nil
        return [.all(.armed(round: round.id))]
    }

    /// Discard the current round (ranking and lockouts) and start a fresh idle round.
    public func reset() -> [Outbound] {
        guard !isEnded else { return [] }
        round = RoundState(id: round.id.next)
        firstBuzzAt = nil
        return [.all(.reset(round: round.id))]
    }

    /// Convenience for the "Next round" button: reset then arm.
    public func nextRound() -> [Outbound] { reset() + arm() }

    /// Adds `points` (may be negative, to undo) to any player who has been in the session, even if
    /// they have since left. The host does not play and cannot score.
    public func award(points: Int, to playerID: PlayerID) -> [Outbound] {
        guard !isEnded, playerID != host.id, knownNames[playerID] != nil else { return [] }
        scores[playerID, default: 0] += points
        return [.all(.scores(scores))]
    }

    public func kick(_ playerID: PlayerID) -> [Outbound] {
        guard !isEnded, playerID != host.id, let peer = playerToPeer.removeValue(forKey: playerID) else { return [] }
        peerToPlayer.removeValue(forKey: peer)
        players.removeAll { $0.id == playerID }
        return [.peer(peer, .kick), .all(.roster(players: players))]
    }

    public func end() -> [Outbound] {
        guard !isEnded else { return [] }
        isEnded = true
        return [.all(.end)]
    }

    // MARK: - Private

    private func handleHello(playerID: PlayerID, name: String, from peer: PeerID) -> [Outbound] {
        guard playerID != host.id else { return [] }
        // Same player reconnecting from a new peer: drop the stale mapping.
        if let oldPeer = playerToPeer[playerID], oldPeer != peer {
            peerToPlayer.removeValue(forKey: oldPeer)
        }
        peerToPlayer[peer] = playerID
        playerToPeer[playerID] = peer
        knownNames[playerID] = name
        if let index = players.firstIndex(where: { $0.id == playerID }) {
            players[index].name = name
        } else {
            players.append(Player(id: playerID, name: name))
        }
        return [.peer(peer, .welcome(snapshot: snapshot)), .all(.roster(players: players))]
    }

    private func handleBuzz(round roundID: RoundID, from peer: PeerID, at now: ContinuousClock.Instant) -> [Outbound] {
        guard let playerID = peerToPlayer[peer], roundID == round.id else { return [] }
        guard !round.lockedOut.contains(playerID) else { return [] }

        switch round.phase {
        case .idle:
            round.lockedOut.insert(playerID)
            return [.peer(peer, .lockout(round: round.id))]
        case .armed, .resolved:
            guard !round.ranking.contains(where: { $0.playerID == playerID }) else { return [] }
            let first = firstBuzzAt ?? now
            firstBuzzAt = first
            round.ranking.append(BuzzEntry(
                playerID: playerID,
                position: round.ranking.count + 1,
                deltaMilliseconds: (now - first).milliseconds
            ))
            round.phase = .resolved
            return [.all(.result(round: round.id, ranking: round.ranking))]
        }
    }
}
