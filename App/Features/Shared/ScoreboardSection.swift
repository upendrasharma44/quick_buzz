import BuzzCore
import SwiftUI

/// Points per player as a `List` section: live on the host console, in the player's scores sheet,
/// and as final standings when the game ends. Players who left keep their points, dimmed.
struct ScoreboardSection: View {
    let standings: [Standing]
    var title = "Scores"
    var me: PlayerID?
    /// Host only: −1 / +1 per row.
    var onAward: ((PlayerID, Int) -> Void)?
    /// Host only: swipe or long-press to remove a present player.
    var onKick: ((PlayerID) -> Void)?

    var body: some View {
        Section(title) {
            if standings.isEmpty {
                Text("No players yet").foregroundStyle(.secondary)
            }
            ForEach(standings) { standing in
                StandingRow(standing: standing, isMe: standing.playerID == me, onAward: onAward)
                    .swipeActions {
                        if let onKick, standing.isPresent {
                            Button("Remove", role: .destructive) { onKick(standing.playerID) }
                        }
                    }
                    .contextMenu {
                        if let onKick, standing.isPresent {
                            Button("Remove \(standing.name)", systemImage: "person.fill.xmark", role: .destructive) {
                                onKick(standing.playerID)
                            }
                        }
                    }
            }
        }
    }
}

private struct StandingRow: View {
    let standing: Standing
    let isMe: Bool
    let onAward: ((PlayerID, Int) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(standing.position)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Avatar(name: standing.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(standing.name).lineLimit(1)
                    if isMe { YouBadge() }
                }
                if !standing.isPresent {
                    Text("Left the game").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(standing.points)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: Double(standing.points)))
            if let onAward {
                AwardButtons { onAward(standing.playerID, $0) }
            }
        }
        .opacity(standing.isPresent ? 1 : 0.55)
        .animation(.snappy, value: standing.points)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(standing.name), \(standing.points) \(standing.points == 1 ? "point" : "points")\(standing.isPresent ? "" : ", left the game")")
    }
}
