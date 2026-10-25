import Testing
@testable import BuzzCore

@Suite("Standings")
struct StandingsTests {
    let host = Player(id: PlayerID(rawValue: "h"), name: "Hana", isHost: true)
    let ava = Player(id: PlayerID(rawValue: "a"), name: "Ava")
    let ben = Player(id: PlayerID(rawValue: "b"), name: "Ben")
    let cleo = Player(id: PlayerID(rawValue: "c"), name: "Cleo")

    @Test func sortedByPointsWithSharedPositions() {
        let rows = Standings.compute(players: [host, ava, ben, cleo],
                                     scores: [ava.id: 2, ben.id: 3, cleo.id: 2], names: [:])
        #expect(rows.map(\.name) == ["Ben", "Ava", "Cleo"])
        #expect(rows.map(\.position) == [1, 2, 2])
        #expect(rows.map(\.points) == [3, 2, 2])
    }

    @Test func hostIsNeverListed() {
        let rows = Standings.compute(players: [host, ava], scores: [host.id: 5], names: [:])
        #expect(rows.map(\.name) == ["Ava"])
    }

    @Test func playersOnZeroAreListed() {
        let rows = Standings.compute(players: [host, ava, ben], scores: [:], names: [:])
        #expect(rows.map(\.name) == ["Ava", "Ben"])
        #expect(rows.allSatisfy { $0.position == 1 && $0.points == 0 })
    }

    @Test func departedScorersStayButRankBelowPresentOnEqualPoints() {
        let gone = PlayerID(rawValue: "g")
        let rows = Standings.compute(players: [host, ava], scores: [ava.id: 1, gone: 1],
                                     names: [gone: "Gil"])
        #expect(rows.map(\.name) == ["Ava", "Gil"])
        #expect(rows.map(\.isPresent) == [true, false])
        #expect(rows.map(\.position) == [1, 1])
    }

    @Test func departedPlayersWithoutPointsDisappear() {
        let rows = Standings.compute(players: [host, ava], scores: [:], names: [PlayerID(rawValue: "g"): "Gil"])
        #expect(rows.map(\.name) == ["Ava"])
    }

    @MainActor
    @Test func enginesExposeStandings() {
        let engine = HostEngine(hostID: host.id, hostName: "Hana")
        _ = engine.receive(.hello(playerID: ava.id, name: "Ava"), from: PeerID(rawValue: "pa"))
        _ = engine.award(points: 1, to: ava.id)
        #expect(engine.standings.map(\.name) == ["Ava"])
        #expect(engine.standings.first?.points == 1)
    }
}
