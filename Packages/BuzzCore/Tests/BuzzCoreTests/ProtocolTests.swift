import Foundation
import Testing
@testable import BuzzCore

@Suite("GameMessage codec")
struct ProtocolTests {
    static let samples: [GameMessage] = {
        let alice = PlayerID(rawValue: "alice")
        let bob = PlayerID(rawValue: "bob")
        let round = RoundID(3)
        let snapshot = SessionSnapshot(
            players: [Player(id: alice, name: "Alice", isHost: true), Player(id: bob, name: "Bob")],
            round: RoundState(id: round, phase: .resolved,
                              ranking: [BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0)],
                              lockedOut: [alice]),
            scores: [bob: 2]
        )
        return [
            .hello(playerID: bob, name: "Bob"),
            .welcome(snapshot: snapshot),
            .roster(players: snapshot.players),
            .armed(round: round),
            .buzz(round: round),
            .result(round: round, ranking: snapshot.round.ranking),
            .lockout(round: round),
            .reset(round: round.next),
            .scores([alice: 1, bob: 5]),
            .kick,
            .end,
            .ping(id: 42),
            .pong(id: 42),
        ]
    }()

    @Test("every message survives a JSON round trip", arguments: samples)
    func roundTrip(message: GameMessage) throws {
        let data = try GameMessageCodec.encode(message)
        #expect(try GameMessageCodec.decode(data) == message)
    }

    @Test("envelope carries the protocol version")
    func versionIsEncoded() throws {
        let data = try GameMessageCodec.encode(.end)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == Envelope.currentVersion)
    }

    @Test("a message from an incompatible version is rejected")
    func unsupportedVersion() throws {
        let data = try JSONEncoder().encode(Envelope(message: .end, version: Envelope.currentVersion + 1))
        #expect(throws: ProtocolError.unsupportedVersion(Envelope.currentVersion + 1)) {
            try GameMessageCodec.decode(data)
        }
    }

    @Test("duration to milliseconds truncates")
    func durationMilliseconds() {
        #expect(Duration.milliseconds(1234).milliseconds == 1234)
        #expect(Duration.microseconds(1999).milliseconds == 1)
        #expect(Duration.zero.milliseconds == 0)
    }
}
