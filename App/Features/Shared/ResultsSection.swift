import BuzzCore
import SwiftUI

/// The current round's ranking as a `List` section, shared by the host console and the player's
/// scores sheet. Times are relative to the first buzz *as the host received it* (arrival order).
struct ResultsSection: View {
    let round: RoundState
    let name: (PlayerID) -> String
    var me: PlayerID?
    /// Host only: adds −1 / +1 controls per row.
    var onAward: ((PlayerID, Int) -> Void)?

    var body: some View {
        Section {
            if round.ranking.isEmpty {
                Text(round.phase == .armed ? "No buzzes yet" : "No round results yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(round.ranking) { entry in
                ResultRow(entry: entry, name: name(entry.playerID), isMe: entry.playerID == me, onAward: onAward)
            }
            if !round.lockedOut.isEmpty {
                Label {
                    Text("Too early: \(round.lockedOut.map(name).sorted().formatted(.list(type: .and)))")
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Round \(round.id.rawValue)")
        }
    }
}

private struct ResultRow: View {
    let entry: BuzzEntry
    let name: String
    let isMe: Bool
    let onAward: ((PlayerID, Int) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            PositionBadge(position: entry.position)
            Avatar(name: name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    if isMe { YouBadge() }
                }
                Text(entry.position == 1 ? "First!" : "+\(entry.deltaMilliseconds) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onAward {
                AwardButtons { onAward(entry.playerID, $0) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.position == 1
            ? "\(name), first"
            : "\(name), number \(entry.position), \(entry.deltaMilliseconds) milliseconds after the winner")
    }
}

/// −1 / +1 controls. Borderless so they work inside a `List` row without selecting the row.
struct AwardButtons: View {
    let award: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { award(-1) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Take back a point")
            Button { award(1) } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("Award a point")
        }
        .font(.title2)
        .buttonStyle(.borderless)
    }
}

struct PositionBadge: View {
    let position: Int

    var body: some View {
        Group {
            if position == 1 {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
            } else {
                Text("\(position)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 24)
    }
}

struct YouBadge: View {
    var body: some View {
        Text("You")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: Capsule())
    }
}
