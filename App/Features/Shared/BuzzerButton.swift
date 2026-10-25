import BuzzCore
import SwiftUI

/// The player's big round buzzer.
///
/// Fires on **touch-down**, not touch-up: the action runs synchronously in the gesture callback,
/// once per touch. Keep it that way: every millisecond between the press and the engine call is
/// added to the player's time (and ADR 0005 will stamp the press here).
struct BuzzerButton: View {
    let status: PlayerStatus
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        let look = Look(status)
        ZStack {
            Circle()
                .fill(look.color.gradient)
                .shadow(color: look.color.opacity(0.45), radius: isPressed ? 8 : 24, y: isPressed ? 4 : 12)
            Circle()
                .strokeBorder(.white.opacity(0.28), lineWidth: 8)
                .padding(10)
            VStack(spacing: 8) {
                Image(systemName: look.symbol)
                    .font(.system(size: 64, weight: .bold))
                    .symbolEffect(.pulse, isActive: status == .ready)
                    .contentTransition(.symbolEffect(.replace))
                Text(look.title)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                if let subtitle = look.subtitle {
                    Text(subtitle)
                        .font(.headline)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(32)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(isPressed ? 0.93 : 1)
        .animation(.spring(duration: 0.18, bounce: 0.4), value: isPressed)
        .animation(.easeInOut(duration: 0.25), value: status)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    action()
                }
                .onEnded { _ in isPressed = false }
        )
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: isPressed) { _, pressed in pressed }
        .sensoryFeedback(trigger: status) { _, new in
            switch new {
            case .ranked(position: 1, _): .success
            case .lockedOut: .error
            default: nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Buzzer")
        .accessibilityValue(look.accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    /// Colour, symbol and text for each player status.
    struct Look {
        let color: Color
        let symbol: String
        let title: String
        let subtitle: String?
        let accessibilityValue: String

        init(_ status: PlayerStatus) {
            switch status {
            case .joining:
                self = Look(.gray, "hourglass", "Joining…", nil, "Joining the game")
            case .waiting:
                self = Look(Color(.systemGray2), "hand.raised.fill", "Get ready", "Wait for the host",
                            "Not live yet. Pressing now locks you out of this round.")
            case .ready:
                self = Look(.red, "bolt.fill", "BUZZ!", nil, "Live. Press to buzz.")
            case .buzzed:
                self = Look(.orange, "checkmark", "Buzzed!", "Waiting for results…", "Buzzed. Waiting for results.")
            case .ranked(position: 1, _):
                self = Look(Color(red: 0.95, green: 0.68, blue: 0.05), "trophy.fill", "First!", nil, "You buzzed first.")
            case .ranked(let position, let delta):
                self = Look(.indigo, "flag.fill", "#\(position)", "+\(delta) ms",
                            "You were number \(position), \(delta) milliseconds after the winner.")
            case .lockedOut:
                self = Look(Color(red: 0.35, green: 0.33, blue: 0.4), "xmark.octagon.fill", "Too early",
                            "Locked out this round", "Too early. Locked out this round.")
            case .kicked, .ended:
                self = Look(.gray, "flag.checkered", "Game over", nil, "The game is over.")
            }
        }

        private init(_ color: Color, _ symbol: String, _ title: String, _ subtitle: String?, _ accessibilityValue: String) {
            self.color = color
            self.symbol = symbol
            self.title = title
            self.subtitle = subtitle
            self.accessibilityValue = accessibilityValue
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([PlayerStatus.waiting, .ready, .buzzed, .ranked(position: 1, deltaMilliseconds: 0),
                     .ranked(position: 2, deltaMilliseconds: 37), .lockedOut], id: \.self) { status in
                BuzzerButton(status: status) {}
                    .frame(width: 260)
            }
        }
        .padding()
    }
}
