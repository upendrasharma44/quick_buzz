import BuzzCore
import SwiftUI

/// Owns the `PlayerSession` from browsing through joining to the end of the game, and shows
/// the screen that matches its phase.
struct JoinFlowView: View {
    /// DEBUG demo/screenshot aid: join the first game that appears.
    var autoJoinFirst = false
    let onExit: () -> Void

    @Environment(Profile.self) private var profile
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: PlayerSession?
    @State private var didAutoJoin = false

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                if let title = exitTitle {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(title) {
                            Task {
                                await session?.leave()
                                onExit()
                            }
                        }
                    }
                }
            }
            .task {
                guard session == nil else { return }
                let created = PlayerSession(
                    playerID: profile.playerID,
                    name: profile.name,
                    transport: await services.makeTransport(profile.name)
                )
                session = created
                await created.start()
            }
            .onChange(of: session?.hosts.first) { _, first in
                guard autoJoinFirst, !didAutoJoin, let first, let session else { return }
                didAutoJoin = true
                Task { await session.join(first) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard let session else { return }
                switch phase {
                case .background: session.sceneDidEnterBackground()
                case .active: Task { await session.sceneDidBecomeActive() }
                default: break
                }
            }
            .onDisappear {
                guard let session else { return }
                Task { await session.leave() }
            }
            .keepsScreenAwake()
    }

    @ViewBuilder private var content: some View {
        if let session {
            switch session.phase {
            case .idle, .browsing, .connecting:
                JoinBrowserView(session: session)
            case .joined, .reconnecting:
                PlayerWaitingView(session: session)
            case .ended(let reason):
                SessionEndedView(reason: reason, onDone: onExit)
            }
        } else {
            ProgressView()
        }
    }

    private var exitTitle: String? {
        switch session?.phase {
        case .joined, .reconnecting: "Leave"
        case .ended: nil
        default: "Cancel"
        }
    }
}
