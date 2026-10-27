import Foundation
import os

/// Opt-in diagnostic log. Sessions and transports record what they do so a game that misbehaves
/// on real phones can be reconstructed afterwards (Settings → Diagnostics, or `-BLDebugLog YES`).
///
/// - Costs one flag check when off; messages are only built when it's on.
/// - Each line carries the **wall-clock** time (to line up logs from two phones) and the seconds
///   since launch (exact gaps within one phone), plus a category.
/// - Lines go to a file in the app container (fetch with `scripts/fetch-logs.sh`, or share it from
///   Settings) and are mirrored to the unified log (Console.app, subsystem
///   `com.upendrasharma.buzzlight`, category `debug`) for live viewing.
/// - The file rotates at `maxFileBytes` (2 MB); the previous file is kept as `debug.log.1`.
///
/// Nothing leaves the phone unless the user shares the file.
public final class DebugLog: @unchecked Sendable {
    public static let shared = DebugLog()

    public enum Category: String, Sendable {
        case app, session, transport
    }

    public static let fileName = "debug.log"

    /// The file rotates at this size (the previous one is kept as `debug.log.1`).
    public let maxFileBytes: Int

    private let lock = NSLock()
    private var enabled = false
    private var directory: URL?
    private var handle: FileHandle?
    private var bytesWritten = 0
    private let started = ContinuousClock.now
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()
    private let logger = Logger(subsystem: "com.upendrasharma.buzzlight", category: "debug")

    public init(maxFileBytes: Int = 2_000_000) {
        self.maxFileBytes = maxFileBytes
    }

    public var isEnabled: Bool { lock.withLock { enabled } }

    /// Where the log file lives (created if needed). Call once at launch, before logging.
    public func configure(directory: URL, enabled: Bool) {
        lock.withLock {
            closeFile()
            self.directory = directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.enabled = enabled
        }
    }

    public func setEnabled(_ on: Bool) {
        lock.withLock {
            enabled = on
            if !on { closeFile() }
        }
    }

    public var currentFileURL: URL? { lock.withLock { directory?.appendingPathComponent(Self.fileName) } }

    public func log(_ category: Category, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        let now = Date()
        lock.withLock {
            guard enabled else { return }
            let elapsed = ContinuousClock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let line = "\(formatter.string(from: now)) +\(String(format: "%.3f", seconds))s [\(category.rawValue)] \(text)\n"
            append(line)
        }
        logger.notice("[\(category.rawValue, privacy: .public)] \(text, privacy: .public)")
    }

    /// The whole log (previous rotation first), for sharing or display.
    public func contents() -> String {
        lock.withLock {
            handle?.synchronizeFile()
            guard let directory else { return "" }
            let current = directory.appendingPathComponent(Self.fileName)
            let previous = directory.appendingPathComponent(Self.fileName + ".1")
            return [previous, current]
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .joined()
        }
    }

    /// Writes `contents()` to a temporary, descriptively named file (for the share sheet).
    public func exportFile(label: String) -> URL? {
        let text = contents()
        guard !text.isEmpty else { return nil }
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeLabel = label.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buzzlight-\(safeLabel.isEmpty ? "device" : safeLabel)-\(stamp).log")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    public var sizeInBytes: Int {
        lock.withLock {
            guard let directory else { return 0 }
            return [Self.fileName, Self.fileName + ".1"].reduce(0) { total, name in
                let path = directory.appendingPathComponent(name).path
                let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
                return total + (size ?? 0)
            }
        }
    }

    public func clear() {
        lock.withLock {
            closeFile()
            guard let directory else { return }
            for name in [Self.fileName, Self.fileName + ".1"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Private (lock held)

    private func append(_ line: String) {
        guard let directory else { return }
        let url = directory.appendingPathComponent(Self.fileName)
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            bytesWritten = Int((try? handle?.seekToEnd()) ?? 0)
        }
        let data = Data(line.utf8)
        try? handle?.write(contentsOf: data)
        bytesWritten += data.count
        if bytesWritten >= maxFileBytes { rotate(directory) }
    }

    private func rotate(_ directory: URL) {
        closeFile()
        let current = directory.appendingPathComponent(Self.fileName)
        let previous = directory.appendingPathComponent(Self.fileName + ".1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: current, to: previous)
    }

    private func closeFile() {
        try? handle?.close()
        handle = nil
        bytesWritten = 0
    }
}

/// Shorthand for `DebugLog.shared.log`. The message is only built when logging is on.
public func debugLog(_ category: DebugLog.Category, _ message: @autoclosure () -> String) {
    DebugLog.shared.log(category, message())
}

extension GameMessage {
    /// One-line description for the debug log (no full payload dumps).
    public var summary: String {
        switch self {
        case .hello(let id, let name): "hello(\(name), id \(id.short))"
        case .welcome(let s): "welcome(\(s.players.count) players, round \(s.round.id) \(s.round.phase.rawValue), \(s.round.ranking.count) ranked)"
        case .roster(let players): "roster(\(players.map(\.name).joined(separator: ", ")))"
        case .armed(let round): "armed(\(round))"
        case .buzz(let round): "buzz(\(round))"
        case .result(let round, let ranking): "result(\(round): \(ranking.map { "\($0.playerID.short)+\($0.deltaMilliseconds)ms" }.joined(separator: " ")))"
        case .lockout(let round): "lockout(\(round))"
        case .reset(let round): "reset(\(round))"
        case .scores(let scores): "scores(\(scores.count))"
        case .kick: "kick"
        case .end: "end"
        case .ping(let id): "ping(\(id))"
        case .pong(let id): "pong(\(id))"
        }
    }
}

extension PlayerID {
    /// First 8 characters, enough to tell players apart in a log.
    public var short: String { String(rawValue.prefix(8)) }
}

extension Outbound {
    var logDescription: String {
        switch to {
        case .all: "\(message.summary) → all"
        case .peers(let peers): "\(message.summary) → \(peers.map(\.rawValue).joined(separator: ", "))"
        }
    }
}

extension TransportEvent {
    var logDescription: String {
        switch self {
        case .hostFound(let host): "hostFound \(host.id) \"\(host.sessionName)\"\(host.isCompatible ? "" : " (incompatible)")"
        case .hostLost(let peer): "hostLost \(peer)"
        case .peerConnected(let peer): "peerConnected \(peer)"
        case .peerDisconnected(let peer): "peerDisconnected \(peer)"
        case .message(let message, let peer, _): "message \(message.summary) from \(peer)"
        case .failed(let error): "failed \(error)"
        }
    }
}
