import BuzzCore
import SwiftUI

/// The host's console: round status, live ranking with awards, scoreboard (with kick), and the
/// Arm / Reset / Next round controls. Replaces the Stage 2 lobby: before anyone joins it *is* the lobby.
struct HostGameView: View {
    let session: HostSession

    @Environment(AppServices.self) private var services

    private var engine: HostEngine { session.engine }
    private var playerCount: Int { engine.players.count - 1 }
    private var phase: RoundPhase { engine.round.phase }
    private var firstBuzzer: PlayerID? { engine.round.ranking.first?.playerID }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.sessionName)
                        .font(.title2.bold())
                    Label("Players nearby can find this game under **Join a game**.", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let notice = session.notice {
                Section { NoticeRow(text: notice) }
            }

            Section { RoundStatus(phase: phase, playerCount: playerCount, winner: firstBuzzer.map(engine.name(of:))) }

            if phase != .idle || !engine.round.lockedOut.isEmpty {
                ResultsSection(round: engine.round, name: engine.name(of:), onAward: award)
            }

            ScoreboardSection(
                standings: engine.standings,
                title: playerCount == 1 ? "1 player" : "\(playerCount) players",
                onAward: award,
                onKick: { id in Task { await session.kick(id) } }
            )
        }
        .animation(.default, value: engine.round)
        .animation(.default, value: engine.players)
        .safeAreaInset(edge: .bottom) { controls }
        .onChange(of: firstBuzzer) { old, new in
            if old == nil, new != nil { services.sound.playBuzz() }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: firstBuzzer) { old, new in old == nil && new != nil }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            switch phase {
            case .idle:
                Button { Task { await session.arm() } } label: {
                    Label("Arm buzzers", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(playerCount == 0)
            case .armed:
                Button { Task { await session.reset() } } label: {
                    Label("Cancel round", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .resolved:
                Button { Task { await session.reset() } } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { Task { await session.nextRound() } } label: {
                    Label("Next round", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private func award(_ id: PlayerID, _ points: Int) {
        Task { await session.award(points: points, to: id) }
    }
}

/// One-line explanation of where the round is and what the host should do next.
private struct RoundStatus: View {
    let phase: RoundPhase
    let playerCount: Int
    let winner: String?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if playerCount == 0 {
                    ProgressView()
                } else {
                    Image(systemName: symbol)
                        .symbolEffect(.pulse, isActive: phase == .armed)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.title)
            .foregroundStyle(phase == .armed ? Color.red : Color.accentColor)
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch phase {
        case .idle: "questionmark.bubble.fill"
        case .armed: "bolt.fill"
        case .resolved: "trophy.fill"
        }
    }

    private var title: String {
        if playerCount == 0 { return "Waiting for players to join…" }
        switch phase {
        case .idle: return "Ask your question"
        case .armed: return "Buzzers are live!"
        case .resolved: return "\(winner ?? "Someone") buzzed first!"
        }
    }

    private var detail: String {
        if playerCount == 0 { return "Up to \(SessionLimits.maxPlayers) players can join." }
        switch phase {
        case .idle: return "Then tap Arm buzzers. Pressing early locks a player out of the round."
        case .armed: return "Waiting for the first buzz."
        case .resolved: return "Award points, then tap Next round."
        }
    }
}
