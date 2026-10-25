# Testing

## Automated

| Layer | Command | What it covers |
|---|---|---|
| Domain | `swift test --package-path Packages/BuzzCore` | Protocol round trips, `HostEngine` arbitration rules, `PlayerEngine` status transitions, host + 2 players over `LoopbackTransport`. Runs on macOS in ~1 s. |
| Transport | `swift test --package-path Packages/BuzzMultipeer` | Constants and construction. Real Multipeer behaviour cannot be unit-tested. |
| App | `xcodebuild test -project QuickBuzz.xcodeproj -scheme QuickBuzz -destination 'platform=iOS Simulator,name=iPhone 17'` | App target links and smoke test, plus both package test targets via the scheme. |

CI (`.github/workflows/ci.yml`) runs all three on every PR.

Rules:
- Every `HostEngine` / `PlayerEngine` behaviour change gets a test in the matching suite first.
- Tests use Swift Testing (`@Test`, `#expect`). Engine tests are `@MainActor`.
- Integration scenarios go through `LoopbackNetwork` so they stay deterministic.

## Manual: two or more physical devices (Stage 2+)

Simulator↔simulator MultipeerConnectivity works intermittently and simulator↔device not at all;
always verify transport changes on hardware.

Setup
1. Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode after `xcodegen generate`), run on ≥ 2 iPhones.
2. All devices on the same Wi-Fi, or Wi-Fi off and Bluetooth on (peer-to-peer path).
3. On first launch accept the *Local Network* permission prompt. If it was denied:
   Settings → Privacy & Security → Local Network → QuickBuzz.

Script (fill in as stages land)
- [ ] Host appears in the Join list within 3 s on every other device; disappears within 10 s after the host stops.
- [ ] Joining shows the player in the host's roster; name is correct; leaving removes them.
- [ ] Arm → every player screen switches to the buzzer within 300 ms.
- [ ] Two players press "simultaneously": host shows a winner and a Δms for the other; no crash, no tie.
- [ ] Press before Arm → that player sees "Too early", cannot buzz this round, is back after Reset.
- [ ] Background the player app during a round, foreground it: reconnects and shows the current state.
- [ ] Host force-quits: players return to Home with an explanation.

## Debugging tips

- `LoopbackNetwork.stop()` emits `.hostLost` then `.peerDisconnected`; a consumer expecting only
  the latter will hang on the first event.
- Log every `Outbound` from the session layer with the round ID; most ordering bugs are visible there.
