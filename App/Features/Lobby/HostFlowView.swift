import BuzzCore
import BuzzMultipeer
import SwiftUI

/// Owns the `HostSession` for as long as the user is hosting.
struct HostFlowView: View {
    let onExit: () -> Void

    @Environment(Profile.self) private var profile
    @Environment(AppServices.self) private var services
    @State private var session: HostSession?
    @State private var confirmingEnd = false

    var body: some View {
        Group {
            if let session {
                HostLobbyView(session: session)
            } else {
                ProgressView("Starting…")
            }
        }
        .navigationTitle("Hosting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End", role: .destructive) {
                    // Nobody to disturb: skip the confirmation.
                    if (session?.engine.players.count ?? 0) > 1 {
                        confirmingEnd = true
                    } else {
                        Task { await endAndExit() }
                    }
                }
            }
        }
        .confirmationDialog("End the game for everyone?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End game", role: .destructive) { Task { await endAndExit() } }
        }
        .task {
            guard session == nil else { return }
            let created = HostSession(
                hostID: profile.playerID,
                hostName: profile.name,
                transport: await services.makeTransport(profile.name)
            )
            session = created
            await created.start()
            services.demo?.hostStarted(created)
        }
        // No scene-phase handling needed: MultipeerConnectivity pauses advertising in the background
        // and resumes it by itself; players reconnect on their own (ADR 0004).
        .onDisappear {
            guard let session else { return }
            Task { await session.end() }
        }
        .keepsScreenAwake()
    }

    private func endAndExit() async {
        await session?.end()
        onExit()
    }
}

/// The host's lobby: session name, live roster, kick, and the (Stage 3) start button.
struct HostLobbyView: View {
    let session: HostSession

    private var others: Int { session.engine.players.count - 1 }

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

            Section {
                ForEach(session.engine.players) { player in
                    PlayerRow(player: player, isMe: player.isHost)
                        .swipeActions {
                            if !player.isHost {
                                Button("Remove", role: .destructive) { Task { await session.kick(player.id) } }
                            }
                        }
                        .contextMenu {
                            if !player.isHost {
                                Button("Remove \(player.name)", systemImage: "person.fill.xmark", role: .destructive) {
                                    Task { await session.kick(player.id) }
                                }
                            }
                        }
                }
                if others == 0 {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for players to join…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(others == 1 ? "1 player" : "\(others) players")
            } footer: {
                Text("Up to \(MultipeerTransport.maxPlayers) players. Swipe left on a player to remove them.")
            }
        }
        .animation(.default, value: session.engine.players)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {} label: {
                    Label("Start round", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
                Text("Buzz rounds arrive in Stage 3.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)
        }
    }
}
