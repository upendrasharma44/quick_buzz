import BuzzCore
import SwiftUI

/// A joined player's screen until rounds start (the buzzer itself arrives in Stage 3).
struct PlayerWaitingView: View {
    let session: PlayerSession

    private var isReconnecting: Bool {
        if case .reconnecting = session.phase { true } else { false }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: status.symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, isActive: status.isPending)
                    Text(status.title)
                        .font(.title3.bold())
                    Text(status.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if isReconnecting {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Connection lost. Reconnecting to the host…")
                    }
                }
            }

            Section("Players") {
                ForEach(session.engine.players) { player in
                    PlayerRow(player: player, isMe: player.id == session.engine.me.id)
                }
            }
        }
        .animation(.default, value: session.engine.players)
        .navigationTitle(session.host?.sessionName ?? "Game")
    }

    private var status: Status {
        switch session.engine.status {
        case .joining:
            Status(symbol: "hourglass", title: "Joining…", detail: "Saying hello to the host.", isPending: true)
        case .waiting:
            Status(symbol: "checkmark.circle.fill", title: "You're in!",
                   detail: "Waiting for the host to start a round.", isPending: false)
        case .ready, .buzzed, .ranked, .lockedOut:
            Status(symbol: "bolt.fill", title: "Round in progress",
                   detail: "The buzzer arrives in the next update.", isPending: false)
        case .kicked, .ended:
            Status(symbol: "xmark.circle", title: "Game over", detail: "", isPending: false)
        }
    }

    private struct Status {
        let symbol: String
        let title: String
        let detail: String
        let isPending: Bool
    }
}

/// Why the player's game ended, with a way back to Home.
struct SessionEndedView: View {
    let reason: PlayerSession.EndReason
    let onDone: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        } actions: {
            Button("Back to Home", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("")
    }

    private var title: String {
        switch reason {
        case .left: "You left the game"
        case .hostEnded: "The host ended the game"
        case .kicked: "You were removed from the game"
        case .connectionLost: "Lost connection to the host"
        case .incompatibleVersion: "Different app versions"
        }
    }

    private var detail: String {
        switch reason {
        case .left, .hostEnded: "Thanks for playing!"
        case .kicked: "The host removed you. You can join another game."
        case .connectionLost: "The host's phone went out of range or closed QuickBuzz."
        case .incompatibleVersion: "Update QuickBuzz on both phones from the App Store and try again."
        }
    }

    private var symbol: String {
        switch reason {
        case .left, .hostEnded: "flag.checkered"
        case .kicked: "person.fill.xmark"
        case .connectionLost: "wifi.exclamationmark"
        case .incompatibleVersion: "arrow.triangle.2.circlepath"
        }
    }
}
