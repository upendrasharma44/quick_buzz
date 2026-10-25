import BuzzCore
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// App side of the debug log (`DebugLog` in BuzzCore): where the file lives, the on/off switch,
/// the header that identifies the phone, and the shareable export.
///
/// Turn on with Settings → Diagnostics → Record debug log, or launch with `-BLDebugLog YES`.
/// Fetch with `scripts/fetch-logs.sh` (phone connected to the Mac) or Settings → Share debug log.
enum Diagnostics {
    /// UserDefaults key (also the launch argument `-BLDebugLog YES`).
    static let enabledKey = "BLDebugLog"

    /// `Library/Application Support/DebugLog/` in the app container.
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("DebugLog", isDirectory: true)
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// Call once at launch.
    @MainActor
    static func start(profile: Profile, defaults: UserDefaults = .standard) {
        DebugLog.shared.configure(directory: directory, enabled: isEnabled(defaults))
        logHeader(profile: profile, reason: "launch")
    }

    @MainActor
    static func setEnabled(_ on: Bool, profile: Profile) {
        if on {
            DebugLog.shared.setEnabled(true)
            logHeader(profile: profile, reason: "enabled")
        } else {
            debugLog(.app, "debug log disabled")
            DebugLog.shared.setEnabled(false)
        }
    }

    /// Identifies the phone and build at the top of each run, so logs from several phones can be told apart.
    @MainActor
    static func logHeader(profile: Profile, reason: String) {
        debugLog(.app, """
            ==== BuzzLight \(Bundle.main.appVersion) (\(reason)) · \(deviceModel) iOS \(UIDevice.current.systemVersion) \
            · player \(profile.name.isEmpty ? "(no name yet)" : profile.name) \(profile.playerID.short) \
            · transport \(TransportKind.current().rawValue) ====
            """)
    }

    /// Hardware identifier, e.g. "iPhone14,7".
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// The debug log as a shareable file, built only when the share sheet asks for it.
struct DebugLogFile: Transferable {
    let label: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            guard let url = DebugLog.shared.exportFile(label: file.label) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(url)
        }
    }
}
