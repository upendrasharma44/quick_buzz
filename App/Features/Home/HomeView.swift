import SwiftUI

/// Landing screen. Stage 0 placeholder: the Host / Join flows arrive in Stage 2.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.tint)
                Text("QuickBuzz")
                    .font(.largeTitle.bold())
                Text("Who buzzed first?")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Host a game") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Join a game") {}
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Text("Coming in Stage 2")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer().frame(height: 24)
            }
            .padding()
            .disabled(true)
        }
    }
}

#Preview {
    HomeView()
}
