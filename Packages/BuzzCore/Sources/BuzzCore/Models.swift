import Foundation

/// Stable identity of a participant. Generated once per device and persisted by the app,
/// so a player keeps the same ID across reconnects within a session.
public struct PlayerID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }

    public var description: String { rawValue }
}

public struct Player: Hashable, Codable, Sendable, Identifiable {
    public let id: PlayerID
    public var name: String
    public var isHost: Bool

    public init(id: PlayerID, name: String, isHost: Bool = false) {
        self.id = id
        self.name = name
        self.isHost = isHost
    }
}

/// Monotonically increasing per session. The host issues a new ID on every reset so that
/// buzzes for an old round can be recognised and discarded.
public struct RoundID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) { self.rawValue = rawValue }

    public var next: RoundID { RoundID(rawValue + 1) }
    public var description: String { "#\(rawValue)" }

    public static func < (lhs: RoundID, rhs: RoundID) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum RoundPhase: String, Codable, Sendable {
    /// Round exists but the host has not armed it yet. Buzzing now is "too early".
    case idle
    /// Buzzes are accepted; nobody has buzzed yet.
    case armed
    /// At least one buzz was accepted. Further buzzes still extend the ranking.
    case resolved
}

/// One accepted buzz, as ranked by the host.
public struct BuzzEntry: Hashable, Codable, Sendable, Identifiable {
    public let playerID: PlayerID
    /// 1-based position in the ranking.
    public let position: Int
    /// Milliseconds after the winning buzz arrived at the host (0 for the winner).
    public let deltaMilliseconds: Int

    public var id: PlayerID { playerID }

    public init(playerID: PlayerID, position: Int, deltaMilliseconds: Int) {
        self.playerID = playerID
        self.position = position
        self.deltaMilliseconds = deltaMilliseconds
    }
}

public struct RoundState: Hashable, Codable, Sendable {
    public var id: RoundID
    public var phase: RoundPhase
    public var ranking: [BuzzEntry]
    /// Players who buzzed before the round was armed; their buzzes are ignored for this round.
    public var lockedOut: Set<PlayerID>

    public init(id: RoundID, phase: RoundPhase = .idle, ranking: [BuzzEntry] = [], lockedOut: Set<PlayerID> = []) {
        self.id = id
        self.phase = phase
        self.ranking = ranking
        self.lockedOut = lockedOut
    }

    public var winner: BuzzEntry? { ranking.first }
}

/// Everything a late joiner needs to render the current screen.
public struct SessionSnapshot: Hashable, Codable, Sendable {
    public var players: [Player]
    public var round: RoundState
    public var scores: [PlayerID: Int]

    public init(players: [Player], round: RoundState, scores: [PlayerID: Int] = [:]) {
        self.players = players
        self.round = round
        self.scores = scores
    }
}

extension Duration {
    /// Whole milliseconds, truncated. Used for ranking deltas shown in the UI.
    public var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
