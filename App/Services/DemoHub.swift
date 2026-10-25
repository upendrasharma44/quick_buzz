import BuzzCore
import Foundation

/// Demo mode: an in-process loopback network with simulated players, so the app can be shown
/// and screenshotted in the simulator without a second device. Only activated in DEBUG builds
/// via `-QBDemo YES` (see `AppServices.live`).
@MainActor
final class DemoHub {
    let network = LoopbackNetwork()
    private var bots: [PlayerSession] = []
    private var demoHost: HostSession?

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
    }

    /// Simulated players join the user's own game one by one.
    func hostStarted(_ session: HostSession) {
        Task {
            for name in ["Cleo", "Dev", "Eli"] {
                try? await Task.sleep(for: .milliseconds(700))
                guard session.phase == .hosting else { return }
                await addBot(name, joining: DiscoveredHost(id: session.localPeer, sessionName: session.sessionName))
            }
        }
    }

    private func addBot(_ name: String, joining host: DiscoveredHost) async {
        bots.removeAll { if case .ended = $0.phase { true } else { false } }
        let bot = PlayerSession(playerID: PlayerID(), name: name, transport: await network.makeTransport(name: name))
        bots.append(bot)
        await bot.start()
        await bot.join(host)
    }
}
