import Foundation
import Testing
@testable import BuzzCore

@MainActor
@Suite("PlayerEngine")
struct PlayerEngineTests {
    let hostID = PlayerID(rawValue: "host")
    let alice = PlayerID(rawValue: "alice")
    let bob = PlayerID(rawValue: "bob")

    var roster: [Player] {
        [Player(id: hostID, name: "Host", isHost: true), Player(id: alice, name: "Alice"), Player(id: bob, name: "Bob")]
    }

    func joined() -> PlayerEngine {
        let engine = PlayerEngine(id: alice, name: "Alice")
        _ = engine.connected()
        _ = engine.receive(.welcome(snapshot: SessionSnapshot(players: roster, round: RoundState(id: RoundID(1)))))
        return engine
    }

    @Test func connectedSendsHello() {
        let engine = PlayerEngine(id: alice, name: "Alice")
        #expect(engine.connected() == [.all(.hello(playerID: alice, name: "Alice"))])
        #expect(engine.status == .joining)
    }

    @Test func welcomePopulatesStateAndWaits() {
        let engine = joined()
        #expect(engine.players == roster)
        #expect(engine.host?.id == hostID)
        #expect(engine.round?.id == RoundID(1))
        #expect(engine.status == .waiting)
    }

    @Test func armedMakesPlayerReadyAndBuzzSendsOnce() {
        let engine = joined()
        _ = engine.receive(.armed(round: RoundID(1)))
        #expect(engine.status == .ready)
        #expect(engine.buzz() == [.all(.buzz(round: RoundID(1)))])
        #expect(engine.status == .buzzed)
        #expect(engine.buzz().isEmpty, "second press is swallowed locally")
    }

    @Test func resultRanksMe() {
        let engine = joined()
        _ = engine.receive(.armed(round: RoundID(1)))
        _ = engine.buzz()
        _ = engine.receive(.result(round: RoundID(1), ranking: [
            BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0),
            BuzzEntry(playerID: alice, position: 2, deltaMilliseconds: 12),
        ]))
        #expect(engine.status == .ranked(position: 2, deltaMilliseconds: 12))
    }

    @Test func resultForSomeoneElseKeepsMeBuzzedOrReady() {
        let engine = joined()
        _ = engine.receive(.armed(round: RoundID(1)))
        _ = engine.receive(.result(round: RoundID(1), ranking: [BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0)]))
        #expect(engine.status == .ready, "can still buzz for a lower position")
        _ = engine.buzz()
        _ = engine.receive(.result(round: RoundID(1), ranking: [BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0)]))
        #expect(engine.status == .buzzed)
    }

    @Test func earlyBuzzIsForwardedAndLockoutApplied() {
        let engine = joined()
        #expect(engine.buzz() == [.all(.buzz(round: RoundID(1)))], "early press still goes to host")
        #expect(engine.status == .waiting)
        _ = engine.receive(.lockout(round: RoundID(1)))
        #expect(engine.status == .lockedOut)
        _ = engine.receive(.armed(round: RoundID(1)))
        #expect(engine.status == .lockedOut)
        #expect(engine.buzz().isEmpty)
    }

    @Test func resetReturnsToWaiting() {
        let engine = joined()
        _ = engine.receive(.lockout(round: RoundID(1)))
        _ = engine.receive(.reset(round: RoundID(2)))
        #expect(engine.status == .waiting)
        #expect(engine.round == RoundState(id: RoundID(2)))
    }

    @Test func rosterScoresKickEnd() {
        let engine = joined()
        _ = engine.receive(.roster(players: Array(roster.prefix(2))))
        #expect(engine.players.count == 2)
        _ = engine.receive(.scores([alice: 4]))
        #expect(engine.scores == [alice: 4])
        _ = engine.receive(.kick)
        #expect(engine.status == .kicked)
        _ = engine.receive(.armed(round: RoundID(1)))
        #expect(engine.status == .kicked, "state updates never resurrect a kicked player")

        let other = joined()
        _ = other.receive(.end)
        #expect(other.status == .ended)
    }

    @Test func disconnectedEndsUnlessKicked() {
        let engine = joined()
        engine.disconnected()
        #expect(engine.status == .ended)
        let kicked = joined()
        _ = kicked.receive(.kick)
        kicked.disconnected()
        #expect(kicked.status == .kicked)
    }

    @Test func pingIsAnswered() {
        let engine = joined()
        #expect(engine.receive(.ping(id: 9)) == [.all(.pong(id: 9))])
    }

    @Test func buzzBeforeWelcomeIsIgnored() {
        let engine = PlayerEngine(id: alice, name: "Alice")
        _ = engine.connected()
        #expect(engine.buzz().isEmpty)
    }
}

@MainActor
@Suite("PlayerEngine buzz re-send")
struct PlayerEngineResendTests {
    let hostID = PlayerID(rawValue: "host")
    let alice = PlayerID(rawValue: "alice")
    let bob = PlayerID(rawValue: "bob")

    func armedAndBuzzed() -> PlayerEngine {
        let engine = PlayerEngine(id: alice, name: "Alice")
        _ = engine.connected()
        let players = [Player(id: hostID, name: "Host", isHost: true), Player(id: alice, name: "Alice")]
        _ = engine.receive(.welcome(snapshot: SessionSnapshot(players: players, round: RoundState(id: RoundID(1)))))
        _ = engine.receive(.armed(round: RoundID(1)))
        _ = engine.buzz()
        return engine
    }

    func welcome(_ round: RoundState) -> GameMessage {
        .welcome(snapshot: SessionSnapshot(players: [Player(id: hostID, name: "Host", isHost: true)], round: round))
    }

    @Test func buzzLostWithTheLinkIsResentAfterReconnect() {
        let engine = armedAndBuzzed()
        #expect(engine.unconfirmedBuzz == RoundID(1))
        _ = engine.connected()  // reconnect
        let out = engine.receive(welcome(RoundState(id: RoundID(1), phase: .armed)))
        #expect(out == [.all(.buzz(round: RoundID(1)))])
        #expect(engine.status == .buzzed, "the button keeps saying Buzzed, not BUZZ! again")
    }

    @Test func buzzThatArrivedIsNotResent() {
        let engine = armedAndBuzzed()
        _ = engine.connected()
        let ranked = RoundState(id: RoundID(1), phase: .resolved,
                                ranking: [BuzzEntry(playerID: alice, position: 1, deltaMilliseconds: 0)])
        #expect(engine.receive(welcome(ranked)).isEmpty)
        #expect(engine.status == .ranked(position: 1, deltaMilliseconds: 0))
        #expect(engine.unconfirmedBuzz == nil)
    }

    @Test func nothingIsResentOnceTheRoundMovedOn() {
        let engine = armedAndBuzzed()
        _ = engine.connected()
        #expect(engine.receive(welcome(RoundState(id: RoundID(2), phase: .armed))).isEmpty)
        #expect(engine.unconfirmedBuzz == nil)
    }

    @Test func resultConfirmsTheBuzz() {
        let engine = armedAndBuzzed()
        _ = engine.receive(.result(round: RoundID(1), ranking: [
            BuzzEntry(playerID: bob, position: 1, deltaMilliseconds: 0),
            BuzzEntry(playerID: alice, position: 2, deltaMilliseconds: 40),
        ]))
        #expect(engine.unconfirmedBuzz == nil)
    }

    @Test func earlyPressIsNeverResent() {
        let engine = PlayerEngine(id: alice, name: "Alice")
        _ = engine.connected()
        _ = engine.receive(.welcome(snapshot: SessionSnapshot(players: [], round: RoundState(id: RoundID(1)))))
        _ = engine.buzz()  // waiting: an early press
        #expect(engine.unconfirmedBuzz == nil)
    }
}
