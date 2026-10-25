import Foundation

/// One line of the scoreboard.
public struct Standing: Hashable, Sendable, Identifiable {
    public let playerID: PlayerID
    public let name: String
    public let points: Int
    /// Shared by players on equal points ("1, 1, 3").
    public let position: Int
    /// `false` once the player has left the session (their points still count).
    public let isPresent: Bool

    public var id: PlayerID { playerID }
}

public enum Standings {
    /// Scoreboard for everyone who can score: present players (even on zero points) and departed
    /// players who scored. The host does not play and is never listed.
    /// Order: points (high first), then present before departed, then name.
    public static func compute(
        players: [Player],
        scores: [PlayerID: Int],
        names: [PlayerID: String]
    ) -> [Standing] {
        let hostIDs = Set(players.filter(\.isHost).map(\.id))
        let presentIDs = Set(players.map(\.id))
        var ids = players.filter { !$0.isHost }.map(\.id)
        for id in scores.keys where !presentIDs.contains(id) && !hostIDs.contains(id) { ids.append(id) }

        let rows = ids.map { id in
            (id: id,
             name: players.first { $0.id == id }?.name ?? names[id] ?? "?",
             points: scores[id] ?? 0,
             present: presentIDs.contains(id))
        }
        .sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.present != $1.present { return $0.present }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        var result: [Standing] = []
        for (index, row) in rows.enumerated() {
            let position = index > 0 && rows[index - 1].points == row.points ? result[index - 1].position : index + 1
            result.append(Standing(playerID: row.id, name: row.name, points: row.points,
                                   position: position, isPresent: row.present))
        }
        return result
    }
}

extension HostEngine {
    public var standings: [Standing] { Standings.compute(players: players, scores: scores, names: knownNames) }
}

extension PlayerEngine {
    public var standings: [Standing] { Standings.compute(players: players, scores: scores, names: knownNames) }
}
