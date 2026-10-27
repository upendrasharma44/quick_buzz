import Foundation
import Testing
@testable import BuzzLight

@Suite("Diagnostics defaults")
struct DiagnosticsDefaultsTests {
    @Test func debugBuildsRecordUnlessTurnedOff() {
        let suite = "DiagnosticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #if DEBUG
        #expect(Diagnostics.isEnabled(defaults), "test phones record without anyone remembering the toggle")
        #else
        #expect(!Diagnostics.isEnabled(defaults))
        #endif
        defaults.set(false, forKey: Diagnostics.enabledKey)
        #expect(!Diagnostics.isEnabled(defaults), "an explicit off wins")
    }
}
