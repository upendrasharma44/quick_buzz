import BuzzCore
import SwiftUI

/// End of a game for host or player: why it ended, final standings (if anyone scored), and a way home.
struct EndOfGameView: View {
    let symbol: String
    let title: String
    let detail: String
    let standings: [Standing]
    var me: PlayerID?
    let onDone: () -> Void

    private var anyoneScored: Bool { standings.contains { $0.points != 0 } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.title2.bold())
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            if anyoneScored {
                ScoreboardSection(standings: standings, title: "Final scores", me: me)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Back to Home").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }
}

/// Why a player's game ended, with the final standings they last saw.
struct SessionEndedView: View {
    let reason: PlayerSession.EndReason
    let standings: [Standing]
    let me: PlayerID
    let onDone: () -> Void

    var body: some View {
        EndOfGameView(symbol: symbol, title: title, detail: detail, standings: standings, me: me, onDone: onDone)
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
