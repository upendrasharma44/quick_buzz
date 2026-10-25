import BuzzCore
import SwiftUI

/// A joined player's screen: the buzzer, the round's outcome, and a scores sheet.
/// Replaces the Stage 2 waiting screen; before the first round the buzzer simply says "Get ready".
struct PlayerGameView: View {
    let session: PlayerSession

    @Environment(AppServices.self) private var services
    @State private var showingScores = false

    private var engine: PlayerEngine { session.engine }
    private var myPoints: Int { engine.scores[engine.me.id] ?? 0 }
    private var winner: PlayerID? { engine.round?.ranking.first?.playerID }
    private var isReconnecting: Bool {
        if case .reconnecting = session.phase { true } else { false }
    }

    var body: some View {
        VStack(spacing: 20) {
            if isReconnecting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Connection lost. Reconnecting to the host…")
                }
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Label("\(myPoints) \(myPoints == 1 ? "point" : "points")", systemImage: "star.fill")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(value: Double(myPoints)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.12), in: Capsule())
                Spacer()
                if let round = engine.round {
                    Text("Round \(round.id.rawValue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            BuzzerButton(status: engine.status, action: press)
                .frame(maxWidth: 360)
                .padding(.horizontal, 12)
                .disabled(isReconnecting)
                .opacity(isReconnecting ? 0.5 : 1)

            Text(caption)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .animation(.default, value: caption)

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(session.host?.sessionName ?? "Game")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Scores", systemImage: "list.number") { showingScores = true }
            }
        }
        .sheet(isPresented: $showingScores) {
            PlayerScoresSheet(session: session)
        }
        .onChange(of: winner) { _, new in
            guard let new else { return }
            let line = new == engine.me.id ? "You buzzed first" : "\(engine.name(of: new)) buzzed first"
            AccessibilityNotification.Announcement(line).post()
        }
        .task { services.sound.prepare() }
    }

    /// Called from the buzzer's touch-down. Engine first, then sound: nothing may delay the press.
    private func press() {
        let wasLive = engine.status == .ready
        session.buzz()
        if wasLive { services.sound.playBuzz() }
    }

    private var caption: String {
        if let winner, winner != engine.me.id {
            return "\(engine.name(of: winner)) buzzed first"
        }
        switch engine.status {
        case .joining: return "Joining…"
        case .waiting: return "Wait for the host to open the buzzers.\nPressing early locks you out."
        case .ready: return "Buzzers are live!"
        case .buzzed: return "Waiting for the host…"
        case .ranked(position: 1, _): return "You buzzed first!"
        case .ranked: return ""
        case .lockedOut: return "You pressed before the buzzers opened."
        case .kicked, .ended: return ""
        }
    }
}

/// Current round and scoreboard for a player.
private struct PlayerScoresSheet: View {
    let session: PlayerSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let round = session.engine.round, round.phase != .idle || !round.lockedOut.isEmpty {
                    ResultsSection(round: round, name: session.engine.name(of:), me: session.engine.me.id)
                }
                ScoreboardSection(standings: session.engine.standings, me: session.engine.me.id)
                if let host = session.engine.host {
                    Section("Host") { PlayerRow(player: host, isMe: false) }
                }
            }
            .navigationTitle("Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
