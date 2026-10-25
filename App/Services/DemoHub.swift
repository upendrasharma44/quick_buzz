import BuzzCore
import Foundation

/// Demo mode: an in-process loopback network with simulated players, so the whole game can be
/// shown and screenshotted in the simulator without a second device. Only activated in DEBUG
/// builds via `-QBDemo YES` (see `AppServices.live`).
///
/// - A joinable game, "Quiz Night (demo)", runs rounds by itself once a real player joins.
/// - When you host, Cleo, Dev and Eli join one by one.
/// - Bots buzz 250–1200 ms after the buzzers open, and sometimes press too early.
/// - `-QBDemoAutoPlay YES` makes your own hosted game run rounds by itself too.
/// - `-QBDemoAutoBuzz fast|early` presses *your* buzzer for you (screenshots of winning / too early).
@MainActor
final class DemoHub {
    enum AutoBuzz: String {
        /// React in 80–150 ms: faster than every bot, so you usually win.
        case fast
        /// Press while the buzzers are still closed: you get locked out.
        case early
    }

    struct Timing {
        var joinInterval: Duration = .milliseconds(700)
        var reaction: ClosedRange<Int> = 250...1200      // ms after `armed`
        var earlyPressChance: Double = 0.1               // per bot per round
        var idleBeforeArm: Duration = .seconds(2)
        var showResults: Duration = .seconds(4)
        var abandonRound: Duration = .seconds(8)
        var poll: Duration = .milliseconds(40)

        static let standard = Timing()
    }

    let network = LoopbackNetwork()
    private let timing: Timing
    private let autoPlayOwnGame: Bool
    private let autoBuzz: AutoBuzz?
    private var bots: [PlayerSession] = []
    private var botIDs: Set<PlayerID> = []
    private var demoHost: HostSession?

    init(timing: Timing = .standard, autoPlayOwnGame: Bool = false, autoBuzz: AutoBuzz? = nil) {
        self.timing = timing
        self.autoPlayOwnGame = autoPlayOwnGame
        self.autoBuzz = autoBuzz
    }

    /// A ready-made game to join from the Join screen, with two players already in it.
    func startDemoHost() async {
        guard demoHost == nil else { return }
        let host = HostSession(
            hostID: PlayerID(),
            hostName: "Quiz Master",
            transport: await network.makeTransport(name: "Quiz Master"),
            sessionName: "Quiz Night (demo)"
        )
        demoHost = host
        await host.start()
        for name in ["Ava", "Ben"] {
            await addBot(name, joining: DiscoveredHost(id: host.localPeer, sessionName: host.sessionName))
        }
        autoPlay(host) { [weak self] engine in
            // Only play while a real person is in the game.
            engine.players.contains { !$0.isHost && !(self?.botIDs.contains($0.id) ?? true) }
        }
    }

    /// Simulated players join the user's own game one by one.
    func hostStarted(_ session: HostSession) {
        Task {
            for name in ["Cleo", "Dev", "Eli"] {
                try? await Task.sleep(for: timing.joinInterval)
                guard session.phase == .hosting else { return }
                await addBot(name, joining: DiscoveredHost(id: session.localPeer, sessionName: session.sessionName))
            }
        }
        if autoPlayOwnGame {
            autoPlay(session) { $0.players.count > 1 }
        }
    }

    /// The user joined a game. With `-QBDemoAutoBuzz`, their buzzer is pressed for them.
    func playerJoined(_ session: PlayerSession) {
        switch autoBuzz {
        case .fast: drive(session, reaction: 80...150, earlyPressChance: 0)
        case .early: drive(session, reaction: 5_000...5_000, earlyPressChance: 1)
        case nil: break
        }
    }

    /// Ends the demo game and every bot (their background loops stop with them).
    func stop() async {
        await demoHost?.end()
        for bot in bots { await bot.leave() }
        bots = []
    }

    // MARK: - Bots

    private func addBot(_ name: String, joining host: DiscoveredHost) async {
        bots.removeAll { if case .ended = $0.phase { true } else { false } }
        let bot = PlayerSession(playerID: PlayerID(), name: name, transport: await network.makeTransport(name: name))
        bots.append(bot)
        botIDs.insert(bot.engine.me.id)
        await bot.start()
        await bot.join(host)
        drive(bot, reaction: timing.reaction, earlyPressChance: timing.earlyPressChance)
    }

    /// Reacts to the player's own screen like a person would.
    private func drive(_ bot: PlayerSession, reaction: ClosedRange<Int>, earlyPressChance: Double) {
        let timing = timing
        Task {
            var reactedTo: RoundID?
            var consideredEarly: RoundID?
            while true {
                try? await Task.sleep(for: timing.poll)
                if case .ended = bot.phase { return }
                guard let round = bot.engine.round?.id else { continue }
                switch bot.engine.status {
                case .ready where reactedTo != round:
                    reactedTo = round
                    try? await Task.sleep(for: .milliseconds(Int.random(in: reaction)))
                    bot.buzz()
                case .waiting where consideredEarly != round:
                    consideredEarly = round
                    guard Double.random(in: 0..<1) < earlyPressChance else { continue }
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 300...1500)))
                    if bot.engine.status == .waiting { bot.buzz() }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Self-running host

    /// Plays rounds on `host` while `shouldPlay` holds: arm after a pause, show results, award the
    /// winner a point, reset. A round nobody buzzes in is abandoned.
    private func autoPlay(_ host: HostSession, shouldPlay: @escaping @MainActor (HostEngine) -> Bool) {
        let timing = timing
        Task {
            var phaseSince = ContinuousClock.now
            var lastPhase = host.engine.round.phase
            var lastRound = host.engine.round.id
            while host.phase != .ended {
                try? await Task.sleep(for: timing.poll)
                let engine = host.engine
                if engine.round.phase != lastPhase || engine.round.id != lastRound {
                    (lastPhase, lastRound, phaseSince) = (engine.round.phase, engine.round.id, .now)
                }
                guard host.phase == .hosting, shouldPlay(engine) else {
                    phaseSince = .now
                    continue
                }
                let elapsed = ContinuousClock.now - phaseSince
                switch engine.round.phase {
                case .idle where elapsed >= timing.idleBeforeArm:
                    await host.arm()
                case .armed where elapsed >= timing.abandonRound:
                    await host.reset()
                case .resolved where elapsed >= timing.showResults:
                    if let winner = engine.round.winner?.playerID {
                        await host.award(points: 1, to: winner)
                    }
                    await host.reset()
                default:
                    break
                }
            }
        }
    }
}
