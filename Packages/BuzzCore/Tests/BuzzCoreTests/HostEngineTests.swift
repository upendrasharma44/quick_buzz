import Foundation
import Testing
@testable import BuzzCore

@MainActor
@Suite("HostEngine")
struct HostEngineTests {
    let hostID = PlayerID(rawValue: "host")
    let alice = PlayerID(rawValue: "alice")
    let bob = PlayerID(rawValue: "bob")
    let carol = PlayerID(rawValue: "carol")
    let peerA = PeerID(rawValue: "peer-a")
    let peerB = PeerID(rawValue: "peer-b")
    let peerC = PeerID(rawValue: "peer-c")
    let t0 = ContinuousClock.now

    /// Engine with Alice and Bob already joined.
    func lobby() -> HostEngine {
        let engine = HostEngine(hostID: hostID, hostName: "Host")
        _ = engine.peerConnected(peerA)
        _ = engine.receive(.hello(playerID: alice, name: "Alice"), from: peerA)
        _ = engine.peerConnected(peerB)
        _ = engine.receive(.hello(playerID: bob, name: "Bob"), from: peerB)
        return engine
    }

    // MARK: Roster

    @Test func hostIsFirstInRoster() {
        let engine = HostEngine(hostID: hostID, hostName: "Host")
        #expect(engine.players == [Player(id: hostID, name: "Host", isHost: true)])
        #expect(engine.round == RoundState(id: RoundID(1)))
    }

    @Test func helloAddsPlayerAndRepliesWithWelcomeThenRoster() {
        let engine = HostEngine(hostID: hostID, hostName: "Host")
        let out = engine.receive(.hello(playerID: alice, name: "Alice"), from: peerA)
        let expectedPlayers = [Player(id: hostID, name: "Host", isHost: true), Player(id: alice, name: "Alice")]
        #expect(out == [
            .peer(peerA, .welcome(snapshot: SessionSnapshot(players: expectedPlayers, round: RoundState(id: RoundID(1))))),
            .all(.roster(players: expectedPlayers)),
        ])
        #expect(engine.player(for: peerA)?.id == alice)
    }

    @Test func helloAgainRenamesInsteadOfDuplicating() {
        let engine = lobby()
        _ = engine.receive(.hello(playerID: alice, name: "Alicia"), from: peerA)
        #expect(engine.players.filter { $0.id == alice }.map(\.name) == ["Alicia"])
    }

    @Test func reconnectFromNewPeerReplacesMapping() {
        let engine = lobby()
        let peerA2 = PeerID(rawValue: "peer-a2")
        _ = engine.receive(.hello(playerID: alice, name: "Alice"), from: peerA2)
        #expect(engine.player(for: peerA2)?.id == alice)
        #expect(engine.player(for: peerA) == nil)
        #expect(engine.players.count == 3)
    }

    @Test func disconnectRemovesPlayerAndBroadcastsRoster() {
        let engine = lobby()
        let out = engine.peerDisconnected(peerA)
        #expect(engine.players.map(\.id) == [hostID, bob])
        #expect(out == [.all(.roster(players: engine.players))])
        #expect(engine.peerDisconnected(peerA).isEmpty, "unknown peer is a no-op")
    }

    @Test func buzzFromPeerWithoutHelloIsIgnored() {
        let engine = lobby()
        _ = engine.arm()
        #expect(engine.receive(.buzz(round: RoundID(1)), from: peerC).isEmpty)
        #expect(engine.round.ranking.isEmpty)
    }

    // MARK: Rounds

    @Test func armOpensRound() {
        let engine = lobby()
        #expect(engine.arm() == [.all(.armed(round: RoundID(1)))])
        #expect(engine.round.phase == .armed)
        #expect(engine.arm().isEmpty, "arming twice is a no-op")
    }

    @Test func firstBuzzWinsAndRankingUsesHostArrivalOrder() {
        let engine = lobby()
        _ = engine.arm()

        let out1 = engine.receive(.buzz(round: RoundID(1)), from: peerB, at: t0)
        let out2 = engine.receive(.buzz(round: RoundID(1)), from: peerA, at: t0 + .milliseconds(37))

        let expected = [
            BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0),
            BuzzEntry(playerID: alice, position: 2, deltaMilliseconds: 37),
        ]
        #expect(out1 == [.all(.result(round: RoundID(1), ranking: [expected[0]]))])
        #expect(out2 == [.all(.result(round: RoundID(1), ranking: expected))])
        #expect(engine.round.phase == .resolved)
        #expect(engine.round.winner?.playerID == bob)
    }

    @Test func duplicateBuzzIsDropped() {
        let engine = lobby()
        _ = engine.arm()
        _ = engine.receive(.buzz(round: RoundID(1)), from: peerA, at: t0)
        let out = engine.receive(.buzz(round: RoundID(1)), from: peerA, at: t0 + .milliseconds(5))
        #expect(out.isEmpty)
        #expect(engine.round.ranking.count == 1)
    }

    @Test func earlyBuzzLocksPlayerOutForTheRound() {
        let engine = lobby()
        let early = engine.receive(.buzz(round: RoundID(1)), from: peerA)
        #expect(early == [.peer(peerA, .lockout(round: RoundID(1)))])
        #expect(engine.round.lockedOut == [alice])

        _ = engine.arm()
        #expect(engine.receive(.buzz(round: RoundID(1)), from: peerA).isEmpty, "locked-out buzz ignored")
        _ = engine.receive(.buzz(round: RoundID(1)), from: peerB)
        #expect(engine.round.ranking.map(\.playerID) == [bob])
    }

    @Test func staleRoundBuzzIsIgnored() {
        let engine = lobby()
        _ = engine.arm()
        _ = engine.reset()
        _ = engine.arm()
        #expect(engine.receive(.buzz(round: RoundID(1)), from: peerA).isEmpty)
        #expect(engine.round.ranking.isEmpty)
        #expect(engine.round.id == RoundID(2))
    }

    @Test func resetIssuesFreshIdleRoundAndClearsLockouts() {
        let engine = lobby()
        _ = engine.receive(.buzz(round: RoundID(1)), from: peerA)  // lockout
        _ = engine.arm()
        _ = engine.receive(.buzz(round: RoundID(1)), from: peerB)

        let out = engine.reset()
        #expect(out == [.all(.reset(round: RoundID(2)))])
        #expect(engine.round == RoundState(id: RoundID(2)))
    }

    @Test func nextRoundResetsThenArms() {
        let engine = lobby()
        _ = engine.arm()
        let out = engine.nextRound()
        #expect(out == [.all(.reset(round: RoundID(2))), .all(.armed(round: RoundID(2)))])
        #expect(engine.round.phase == .armed)
    }

    // MARK: Scores, kick, end

    @Test func awardAccumulatesAndBroadcasts() {
        let engine = lobby()
        _ = engine.award(points: 1, to: alice)
        let out = engine.award(points: 2, to: alice)
        #expect(out == [.all(.scores([alice: 3]))])
        #expect(engine.award(points: 1, to: carol).isEmpty, "unknown player")
    }

    @Test func kickNotifiesPlayerAndUpdatesRoster() {
        let engine = lobby()
        let out = engine.kick(alice)
        #expect(out == [.peer(peerA, .kick), .all(.roster(players: engine.players))])
        #expect(engine.players.map(\.id) == [hostID, bob])
        #expect(engine.kick(hostID).isEmpty, "host cannot be kicked")
        #expect(engine.kick(alice).isEmpty, "already gone")
    }

    @Test func endStopsEverything() {
        let engine = lobby()
        #expect(engine.end() == [.all(.end)])
        #expect(engine.isEnded)
        #expect(engine.arm().isEmpty)
        #expect(engine.end().isEmpty)
        #expect(engine.receive(.hello(playerID: carol, name: "Carol"), from: peerC).isEmpty)
    }

    @Test func pingIsAnsweredWithPong() {
        let engine = lobby()
        #expect(engine.receive(.ping(id: 7), from: peerA) == [.peer(peerA, .pong(id: 7))])
    }
}
