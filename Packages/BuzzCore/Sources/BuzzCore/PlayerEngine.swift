import Foundation
import Observation

/// What the player's screen should show. Derived from host messages only.
public enum PlayerStatus: Hashable, Sendable {
    /// Connected at the transport level, `hello` sent, waiting for `welcome`.
    case joining
    /// In the lobby or between rounds; buzzing now would be too early.
    case waiting
    /// Round is open and this player has not buzzed yet.
    case ready
    /// Buzz sent, host has not ranked it yet.
    case buzzed
    /// Host ranked this player's buzz at `position` (1 = winner).
    case ranked(position: Int, deltaMilliseconds: Int)
    /// Buzzed before the round was armed.
    case lockedOut
    case kicked
    case ended
}

/// Mirror of the host's state for one player, plus the player's own actions.
@MainActor
@Observable
public final class PlayerEngine {
    public let me: Player
    public private(set) var players: [Player] = []
    public private(set) var round: RoundState?
    public private(set) var scores: [PlayerID: Int] = [:]
    public private(set) var status: PlayerStatus = .joining

    public init(id: PlayerID, name: String) {
        me = Player(id: id, name: name)
    }

    public var host: Player? { players.first { $0.isHost } }

    public func name(of playerID: PlayerID) -> String {
        playerID == me.id ? me.name : players.first { $0.id == playerID }?.name ?? "?"
    }

    // MARK: - Transport events

    /// Call once the transport reports `.peerConnected(host)`.
    public func connected() -> [Outbound] {
        status = .joining
        return [.all(.hello(playerID: me.id, name: me.name))]
    }

    public func disconnected() {
        if status != .kicked && status != .ended { status = .ended }
    }

    public func receive(_ message: GameMessage) -> [Outbound] {
        switch message {
        case .welcome(let snapshot):
            players = snapshot.players
            scores = snapshot.scores
            apply(round: snapshot.round)
        case .roster(let players):
            self.players = players
        case .armed(let roundID):
            var r = round ?? RoundState(id: roundID)
            r.id = roundID
            r.phase = .armed
            r.ranking = []
            apply(round: r)
        case .result(let roundID, let ranking):
            var r = round ?? RoundState(id: roundID)
            r.id = roundID
            r.phase = .resolved
            r.ranking = ranking
            apply(round: r)
        case .lockout(let roundID):
            var r = round ?? RoundState(id: roundID)
            r.lockedOut.insert(me.id)
            apply(round: r)
        case .reset(let roundID):
            apply(round: RoundState(id: roundID))
        case .scores(let scores):
            self.scores = scores
        case .kick:
            status = .kicked
        case .end:
            status = .ended
        case .ping(let id):
            return [.all(.pong(id: id))]
        case .hello, .buzz, .pong:
            break
        }
        return []
    }

    // MARK: - Player actions

    /// Press the buzzer. Always forwards to the host when a round is known, so that an early
    /// press is recorded as a lockout by the host rather than silently swallowed.
    public func buzz() -> [Outbound] {
        guard let round, status == .ready || status == .waiting else { return [] }
        if status == .ready { status = .buzzed }
        return [.all(.buzz(round: round.id))]
    }

    // MARK: - Private

    private func apply(round: RoundState) {
        self.round = round
        if status == .kicked || status == .ended { return }
        if round.lockedOut.contains(me.id) {
            status = .lockedOut
        } else if let entry = round.ranking.first(where: { $0.playerID == me.id }) {
            status = .ranked(position: entry.position, deltaMilliseconds: entry.deltaMilliseconds)
        } else {
            switch round.phase {
            case .idle: status = .waiting
            case .armed, .resolved: status = status == .buzzed ? .buzzed : .ready
            }
        }
    }
}
