import Foundation

/// Wire messages exchanged between host and players. See docs/protocol.md.
///
/// Direction legend: P→H player to host, H→P host to one player, H→* host to everyone.
public enum GameMessage: Hashable, Codable, Sendable {
    /// P→H. First message after connecting; introduces the player's stable ID and name.
    case hello(playerID: PlayerID, name: String)
    /// H→P. Acknowledges `hello` and delivers the full state for late joiners.
    case welcome(snapshot: SessionSnapshot)
    /// H→*. Roster changed (join, leave, rename, kick).
    case roster(players: [Player])
    /// H→*. Round is open for buzzing.
    case armed(round: RoundID)
    /// P→H. The player pressed the buzzer for the given round.
    case buzz(round: RoundID)
    /// H→*. Ranking changed (sent on every accepted buzz).
    case result(round: RoundID, ranking: [BuzzEntry])
    /// H→P. The player buzzed before the round was armed and is locked out for it.
    case lockout(round: RoundID)
    /// H→*. Round cleared; a fresh round with this ID is now idle.
    case reset(round: RoundID)
    /// H→*. Scores changed.
    case scores([PlayerID: Int])
    /// H→P. The player was removed by the host.
    case kick
    /// H→*. The session is over.
    case end
    /// Either direction. Used for RTT estimation (Stage 4).
    case ping(id: UInt32)
    case pong(id: UInt32)
}

/// Versioned wrapper so that incompatible builds can refuse each other cleanly.
public struct Envelope: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let message: GameMessage

    public init(message: GameMessage, version: Int = Envelope.currentVersion) {
        self.version = version
        self.message = message
    }
}

public enum ProtocolError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public enum GameMessageCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    public static func encode(_ message: GameMessage) throws -> Data {
        try encoder.encode(Envelope(message: message))
    }

    public static func decode(_ data: Data) throws -> GameMessage {
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.version == Envelope.currentVersion else {
            throw ProtocolError.unsupportedVersion(envelope.version)
        }
        return envelope.message
    }
}
