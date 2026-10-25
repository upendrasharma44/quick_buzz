import BuzzCore
import Foundation
import Observation

/// The local user: a stable `PlayerID` (generated once per install) and a display name,
/// both persisted in `UserDefaults`.
@MainActor
@Observable
final class Profile {
    static let maxNameLength = 24

    let playerID: PlayerID
    private(set) var name: String

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let playerID = "profile.playerID"
        static let name = "profile.name"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Key.playerID), !raw.isEmpty {
            playerID = PlayerID(rawValue: raw)
        } else {
            let fresh = PlayerID()
            defaults.set(fresh.rawValue, forKey: Key.playerID)
            playerID = fresh
        }
        name = defaults.string(forKey: Key.name).flatMap(Self.normalized) ?? ""
    }

    /// `false` until onboarding has collected a name.
    var hasName: Bool { !name.isEmpty }

    /// Trims, collapses runs of whitespace to one space and caps the length.
    /// Returns `nil` when nothing usable is left.
    static func normalized(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxNameLength))
    }

    /// Saves `raw` if it normalizes to a usable name. Returns whether it was saved.
    @discardableResult
    func setName(_ raw: String) -> Bool {
        guard let value = Self.normalized(raw) else { return false }
        name = value
        defaults.set(value, forKey: Key.name)
        return true
    }
}
