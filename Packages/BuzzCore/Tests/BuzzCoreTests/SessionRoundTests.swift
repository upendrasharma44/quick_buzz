import Foundation
import Testing
@testable import BuzzCore

/// Complete rounds driven through `HostSession` / `PlayerSession` over `LoopbackNetwork`:
/// what the Stage 3 host console and buzzer screen do.
@MainActor
@Suite("Rounds over loopback")
struct SessionRoundTests {
    let network = LoopbackNetwork()

    /// Host "Hana" with players already joined and waiting.
    func game(_ names: [String]) async throws -> (HostSession, [PlayerSession]) {
        let host = HostSession(hostID: PlayerID(rawValue: "host"), hostName: "Hana",
                               transport: await network.makeTransport(name: "Hana"), flushDelay: .zero)
        await host.start()
        var players: [PlayerSession] = []
        for name in names {
            let player = PlayerSession(playerID: PlayerID(rawValue: name), name: name,
                                       transport: await network.makeTransport(name: name),
                                       reconnectTimeout: .seconds(5), retryDelay: .milliseconds(10))
            await player.start()
            #expect(await eventually { player.hosts.contains { $0.id == host.localPeer } })
            await player.join(try #require(player.hosts.first { $0.id == host.localPeer }))
            #expect(await eventually { player.engine.status == .waiting })
            players.append(player)
        }
        #expect(await eventually { players.allSatisfy { $0.engine.players.count == names.count + 1 } })
        return (host, players)
    }

    @Test func fullRoundArmBuzzAwardNext() async throws {
        let (host, players) = try await game(["Ava", "Ben", "Cleo"])
        let (ava, ben, cleo) = (players[0], players[1], players[2])

        await host.arm()
        #expect(await eventually { players.allSatisfy { $0.engine.status == .ready } })

        ben.buzz()
        #expect(await eventually { host.engine.round.ranking.count == 1 })
        ava.buzz()
        #expect(await eventually { host.engine.round.ranking.count == 2 })

        #expect(host.engine.round.ranking.map(\.playerID.rawValue) == ["Ben", "Ava"])
        #expect(await eventually { ben.engine.status == .ranked(position: 1, deltaMilliseconds: 0) })
        #expect(await eventually {
            if case .ranked(2, _) = ava.engine.status { true } else { false }
        })
        #expect(await eventually { cleo.engine.round?.ranking.count == 2 }, "spectators see the ranking too")
        #expect(cleo.engine.status == .ready, "Cleo can still buzz for third")

        await host.award(points: 1, to: PlayerID(rawValue: "Ben"))
        #expect(await eventually { players.allSatisfy { $0.engine.scores == [PlayerID(rawValue: "Ben"): 1] } })

        await host.nextRound()
        #expect(host.engine.round.id == RoundID(2))
        #expect(host.engine.round.phase == .armed)
        #expect(await eventually { players.allSatisfy { $0.engine.status == .ready && $0.engine.round?.id == RoundID(2) } })
        #expect(players.allSatisfy { $0.engine.scores[PlayerID(rawValue: "Ben")] == 1 }, "scores carry over")
    }

    @Test func earlyPressLocksOutUntilReset() async throws {
        let (host, players) = try await game(["Ava", "Ben"])
        let ava = players[0]

        ava.buzz()  // round still idle
        #expect(await eventually { ava.engine.status == .lockedOut })
        await host.arm()
        #expect(await eventually { players[1].engine.status == .ready })
        #expect(ava.engine.status == .lockedOut, "arming does not lift the lockout")
        ava.buzz()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(host.engine.round.ranking.isEmpty)

        await host.reset()
        #expect(await eventually { ava.engine.status == .waiting })
    }

    @Test func repeatedTapsCountOnce() async throws {
        let (host, players) = try await game(["Ava"])
        await host.arm()
        #expect(await eventually { players[0].engine.status == .ready })
        for _ in 0..<5 { players[0].buzz() }
        #expect(await eventually { host.engine.round.ranking.count == 1 })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(host.engine.round.ranking.count == 1)
    }

    @Test func buzzBeforeJoiningIsIgnored() async {
        let lonely = PlayerSession(playerID: PlayerID(rawValue: "x"), name: "X",
                                   transport: await network.makeTransport(name: "X"))
        await lonely.start()
        lonely.buzz()
        #expect(lonely.engine.status == .joining)
    }

    @Test func reconnectMidRoundRestoresState() async throws {
        let (host, players) = try await game(["Ava", "Ben"])
        let (ava, ben) = (players[0], players[1])
        await host.arm()
        #expect(await eventually { ava.engine.status == .ready })
        ava.buzz()
        #expect(await eventually { host.engine.round.ranking.count == 1 })

        await network.dropLink(between: host.localPeer, and: ava.localPeer)
        // Ava comes back on her own (too fast to catch her absence; a rejoin moves her to the end
        // of the roster), and the welcome snapshot shows she already won this round.
        #expect(await eventually { host.engine.players.map(\.name) == ["Hana", "Ben", "Ava"] })
        #expect(await eventually { ava.engine.status == .ranked(position: 1, deltaMilliseconds: 0) })
        #expect(ben.engine.status == .ready)
    }

    @Test func departedPlayerStaysNamedForEveryone() async throws {
        let (host, players) = try await game(["Ava", "Ben"])
        let (ava, ben) = (players[0], players[1])
        await host.arm()
        #expect(await eventually { ava.engine.status == .ready })
        ava.buzz()
        #expect(await eventually { ben.engine.round?.ranking.count == 1 })
        await host.award(points: 2, to: PlayerID(rawValue: "Ava"))

        await ava.leave()
        #expect(await eventually { !ben.engine.isPresent(PlayerID(rawValue: "Ava")) })
        #expect(ben.engine.name(of: PlayerID(rawValue: "Ava")) == "Ava")
        #expect(host.engine.name(of: PlayerID(rawValue: "Ava")) == "Ava")

        // Someone joining afterwards still sees who scored.
        let late = PlayerSession(playerID: PlayerID(rawValue: "Late"), name: "Late",
                                 transport: await network.makeTransport(name: "Late"))
        await late.start()
        #expect(await eventually { late.hosts.contains { $0.id == host.localPeer } })
        await late.join(try #require(late.hosts.first { $0.id == host.localPeer }))
        #expect(await eventually { late.engine.status != .joining })
        #expect(late.engine.scores[PlayerID(rawValue: "Ava")] == 2)
        #expect(late.engine.name(of: PlayerID(rawValue: "Ava")) == "Ava")
    }
}
