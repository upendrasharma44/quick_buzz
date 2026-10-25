import AVFoundation
import Foundation

/// Plays the buzzer sound with as little delay as possible: the player is loaded and primed up
/// front, and the audio session is `.ambient` so it mixes with other audio and respects the
/// silent switch. Muted entirely when Settings → Sound effects is off.
@MainActor
final class SoundPlayer {
    static let enabledKey = "settings.sound"

    private let defaults: UserDefaults
    private var buzz: AVAudioPlayer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// Configures the audio session and loads the sounds. Safe to call more than once.
    func prepare() {
        guard buzz == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let url = Bundle.main.url(forResource: "buzz", withExtension: "wav") {
            buzz = try? AVAudioPlayer(contentsOf: url)
            buzz?.prepareToPlay()
        }
    }

    func playBuzz() {
        guard isEnabled else { return }
        prepare()
        buzz?.currentTime = 0
        buzz?.play()
    }
}
