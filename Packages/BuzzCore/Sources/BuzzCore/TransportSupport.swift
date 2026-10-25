import Foundation

/// Game-wide limits shared by every transport and the UI.
public enum SessionLimits {
    /// Players per game, not counting the host. Eight phones in total.
    public static let maxPlayers = 7
}

/// Two-way map between a transport's native peer object (an `MCPeerID`, an `NWEndpoint`, a
/// connection identifier…) and the `PeerID` handles the engines use. Native peers with the same
/// display name stay distinct because each gets its own minted ID.
public struct PeerRegistry<Key: Hashable> {
    private var byKey: [Key: PeerID] = [:]
    private var byPeer: [PeerID: Key] = [:]
    private var minted = 0

    public init() {}

    /// Returns the existing handle for `key`, or mints one labelled with `displayName`.
    public mutating func peerID(for key: Key, displayName: String) -> PeerID {
        if let existing = byKey[key] { return existing }
        minted += 1
        let peer = PeerID(rawValue: "\(displayName)#\(minted)")
        byKey[key] = peer
        byPeer[peer] = key
        return peer
    }

    public func key(for peer: PeerID) -> Key? { byPeer[peer] }

    /// Forgets a peer whose native object is gone for good (e.g. a closed connection).
    public mutating func remove(_ peer: PeerID) {
        guard let key = byPeer.removeValue(forKey: peer) else { return }
        byKey.removeValue(forKey: key)
    }
}

/// Length limits for names sent in discovery (Bonjour instance names and `MCPeerID` display names
/// are both capped at 63 bytes of UTF-8).
public enum PeerName {
    public static let maxDisplayNameBytes = 63

    public static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated(trimmed.isEmpty ? "Player" : trimmed, maxBytes: maxDisplayNameBytes)
    }

    /// Cuts on a `Character` boundary so emoji and accents are never split.
    public static func truncated(_ string: String, maxBytes: Int) -> String {
        var result = ""
        for character in string {
            guard result.utf8.count + String(character).utf8.count <= maxBytes else { break }
            result.append(character)
        }
        return result
    }
}

/// What a host advertises alongside its Bonjour service (TXT record / MC discovery info).
/// Bonjour caps each key=value pair at 255 bytes; the session name is kept well under that.
public enum DiscoveryInfo {
    public static let sessionNameKey = "session"
    public static let versionKey = "v"
    public static let maxSessionNameBytes = 120

    public static func make(sessionName: String) -> [String: String] {
        [
            sessionNameKey: PeerName.truncated(sessionName, maxBytes: maxSessionNameBytes),
            versionKey: String(Envelope.currentVersion),
        ]
    }

    /// Session name to show in the Join list; falls back to the advertised service/peer name.
    public static func sessionName(from info: [String: String]?, fallback: String) -> String {
        guard let name = info?[sessionNameKey], !name.isEmpty else { return fallback }
        return name
    }

    /// Whether the host speaks our protocol version. A host that advertises no version is
    /// assumed compatible (the host's own first-frame check still applies).
    public static func isCompatible(_ info: [String: String]?) -> Bool {
        guard let advertised = info?[versionKey] else { return true }
        return advertised == String(Envelope.currentVersion)
    }
}
