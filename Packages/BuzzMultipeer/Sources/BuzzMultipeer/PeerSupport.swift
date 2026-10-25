import BuzzCore
import Foundation

/// Two-way map between a transport's native peer object and the `PeerID` handles the engines use.
/// Native peers with the same display name stay distinct because each gets its own minted ID.
struct PeerRegistry<Key: Hashable> {
    private var byKey: [Key: PeerID] = [:]
    private var byPeer: [PeerID: Key] = [:]
    private var minted = 0

    /// Returns the existing handle for `key`, or mints one labelled with `displayName`.
    mutating func peerID(for key: Key, displayName: String) -> PeerID {
        if let existing = byKey[key] { return existing }
        minted += 1
        let peer = PeerID(rawValue: "\(displayName)#\(minted)")
        byKey[key] = peer
        byPeer[peer] = key
        return peer
    }

    func key(for peer: PeerID) -> Key? { byPeer[peer] }
}

/// Limits imposed by MultipeerConnectivity on names and discovery info.
enum PeerName {
    /// `MCPeerID.displayName` must be non-empty and at most 63 bytes of UTF-8.
    static let maxDisplayNameBytes = 63

    static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated(trimmed.isEmpty ? "Player" : trimmed, maxBytes: maxDisplayNameBytes)
    }

    /// Cuts on a `Character` boundary so emoji and accents are never split.
    static func truncated(_ string: String, maxBytes: Int) -> String {
        var result = ""
        for character in string {
            guard result.utf8.count + String(character).utf8.count <= maxBytes else { break }
            result.append(character)
        }
        return result
    }
}

/// The advertiser's discovery info dictionary. Bonjour TXT records cap each key=value pair at
/// 255 bytes; we keep the session name well under that.
enum DiscoveryInfo {
    static let sessionNameKey = "session"
    static let versionKey = "v"
    static let maxSessionNameBytes = 120

    static func make(sessionName: String) -> [String: String] {
        [
            sessionNameKey: PeerName.truncated(sessionName, maxBytes: maxSessionNameBytes),
            versionKey: String(Envelope.currentVersion),
        ]
    }

    /// Session name to show in the Join list; falls back to the peer's display name.
    static func sessionName(from info: [String: String]?, fallback: String) -> String {
        guard let name = info?[sessionNameKey], !name.isEmpty else { return fallback }
        return name
    }

    /// Whether the host speaks our protocol version. A host that advertises no version is
    /// assumed compatible (the invitation context check on the host still applies).
    static func isCompatible(_ info: [String: String]?) -> Bool {
        guard let advertised = info?[versionKey] else { return true }
        return advertised == String(Envelope.currentVersion)
    }
}
