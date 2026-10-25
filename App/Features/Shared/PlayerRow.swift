import BuzzCore
import SwiftUI

/// One roster entry: avatar, name, "You" badge, crown for the host.
struct PlayerRow: View {
    let player: Player
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: player.name)
            Text(player.name)
                .lineLimit(1)
            if isMe {
                Text("You")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
            Spacer()
            if player.isHost {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Host")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Initials on a colour picked deterministically from the name.
struct Avatar: View {
    let name: String

    private static let palette: [Color] = [.orange, .pink, .purple, .indigo, .teal, .green, .blue, .red]

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var color: Color {
        // String.hashValue is randomised per launch; a byte sum keeps colours stable.
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Inline warning used for transport problems and failed joins.
struct NoticeRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
    }
}

extension View {
    /// Disables auto-lock while the view is on screen: locking the phone drops the connection.
    func keepsScreenAwake() -> some View {
        onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
