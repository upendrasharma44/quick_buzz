import Foundation
@testable import BuzzCore

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
/// Sessions process transport events on their own task, so tests wait for observable effects.
@MainActor
func eventually(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Test double whose events are injected by the test and whose outgoing traffic is recorded.
/// Models what LoopbackTransport cannot: frames from peers other than the host (a mesh transport),
/// version-mismatch errors, and hosts that never answer.
final class ScriptedTransport: GameTransport, @unchecked Sendable {
    struct Sent: Equatable { let message: GameMessage; let to: [PeerID]? }  // nil = broadcast

    let localPeer = PeerID(rawValue: "scripted")
    let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let autoConnect: Bool
    private let lock = NSLock()
    private var _sent: [Sent] = []
    private var _connectCalls: [PeerID] = []
    private var _disconnectCalls: [PeerID] = []

    /// - Parameter autoConnect: answer `connect(to:)` with `.peerConnected` (a host that accepts).
    init(autoConnect: Bool = true) {
        self.autoConnect = autoConnect
        (events, continuation) = AsyncStream.makeStream()
    }

    var sent: [Sent] { lock.withLock { _sent } }
    var connectCalls: [PeerID] { lock.withLock { _connectCalls } }
    var disconnectCalls: [PeerID] { lock.withLock { _disconnectCalls } }

    func emit(_ event: TransportEvent) { continuation.yield(event) }

    func startHosting(sessionName: String) async throws {}
    func startBrowsing() async throws {}
    func stopBrowsing() async {}
    func connect(to host: PeerID) async throws {
        lock.withLock { _connectCalls.append(host) }
        if autoConnect { emit(.peerConnected(host)) }
    }
    func send(_ message: GameMessage, to peers: [PeerID]) async throws {
        lock.withLock { _sent.append(Sent(message: message, to: peers)) }
    }
    func broadcast(_ message: GameMessage) async throws {
        lock.withLock { _sent.append(Sent(message: message, to: nil)) }
    }
    func disconnect(_ peer: PeerID) async {
        lock.withLock { _disconnectCalls.append(peer) }
        emit(.peerDisconnected(peer))
    }
    func stop() async { continuation.finish() }
}
