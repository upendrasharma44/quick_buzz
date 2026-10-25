import BuzzCore
import SwiftUI

/// Owns the `HostSession` for as long as the user is hosting: the console while the game runs,
/// then the final standings.
struct HostFlowView: View {
    let onExit: () -> Void

    @Environment(Profile.self) private var profile
    @Environment(AppServices.self) private var services
    @State private var session: HostSession?
    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            if let session {
                if session.phase == .ended {
                    EndOfGameView(
                        symbol: "flag.checkered",
                        title: "Game over",
                        detail: winnerLine(session.engine.standings),
                        standings: session.engine.standings,
                        onDone: onExit
                    )
                } else {
                    HostGameView(session: session)
                }
            } else {
                ProgressView("Starting…")
            }
        }
        .navigationTitle(session?.phase == .ended ? "" : "Hosting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            if session?.phase != .ended {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End", role: .destructive) {
                        // Nobody to disturb: skip the confirmation and the standings.
                        if (session?.engine.players.count ?? 0) > 1 {
                            confirmingEnd = true
                        } else {
                            Task {
                                await session?.end()
                                onExit()
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("End the game for everyone?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End game", role: .destructive) { Task { await session?.end() } }
        }
        .task {
            guard session == nil else { return }
            services.sound.prepare()
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

    private func winnerLine(_ standings: [Standing]) -> String {
        let leaders = standings.filter { $0.position == 1 && $0.points > 0 }.map(\.name)
        guard !leaders.isEmpty else { return "Thanks for hosting!" }
        return leaders.count == 1 ? "\(leaders[0]) wins!" : "Tie between \(leaders.formatted(.list(type: .and)))!"
    }
}
