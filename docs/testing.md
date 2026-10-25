# Testing

## Automated

| Layer | Command | What it covers |
|---|---|---|
| Domain + sessions | `swift test --package-path Packages/BuzzCore` | 72 tests. Protocol round trips; `HostEngine` arbitration; `PlayerEngine` statuses; loopback contract; `HostSession`/`PlayerSession` over `LoopbackTransport` (discovery, join, same-name players, failed and timed-out joins, leave, kick, host end, host crash → connection lost, drop → reconnect with score kept) and over `ScriptedTransport` (player traffic goes to the host only, mesh frames and other peers' version errors ignored, incompatible hosts not joinable, reconnect deadline paused in background, late link usable on retry); full rounds through sessions (arm → buzz order → results everywhere → award → next round, early-press lockout, repeated taps, reconnect mid-round, departed names for late joiners); `Standings`. ~0.5 s. |
| Transport | `swift test --package-path Packages/BuzzMultipeer` | Service type, player cap, invitation timeout/expiry ordering, version checks (discovery info + invitation context), `PeerRegistry`, display-name sanitising, discovery-info limits, send/connect error paths, `stop()` semantics. |
| Transport, live | `BUZZLIGHT_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer` | **Real MultipeerConnectivity** between two transports on this Mac: discover → invite → connect → messages both ways → disconnect; invitation through a fresh browser (regression: fails in ~20 s without the deferral, passes in ~1 s with it); the full `HostSession`/`PlayerSession` stack joining, syncing the roster and ending. ~5 s. Opt-in (needs the local network); not run in CI. macOS may ask for Local Network permission for your terminal the first time. |
| App | `xcodebuild test -project BuzzLight.xcodeproj -scheme BuzzLight -destination 'platform=iOS Simulator,name=iPhone 17'` | 10 tests: `Profile` persistence and name rules; demo mode (bots join, bots buzz after arming, auto-play advances rounds and awards points, demo host plays with a real player); smoke test. Plus both package test targets via the scheme. |

CI (`.github/workflows/ci.yml`) runs the package and app suites on every PR.

Rules:
- Every engine or session behaviour change gets a test in the matching suite first.
- Tests use Swift Testing (`@Test`, `#expect`). Engine and session tests are `@MainActor`.
- Session tests wait with `eventually { … }` (`Tests/BuzzCoreTests/TestSupport.swift`), never fixed sleeps,
  and inject short timeouts (`connectTimeout`, `reconnectTimeout`, `retryDelay`, `flushDelay: .zero`).
- Integration scenarios go through `LoopbackNetwork`; use `dropLink(between:and:)` to simulate a
  transient disconnect and `transport.stop()` to simulate a crash.

## Demo mode (simulator, DEBUG builds)

Runs the whole UI on a loopback network with simulated players — no second device needed.
Launch arguments (also available as unticked toggles in Xcode → Edit Scheme → Run → Arguments):

| Argument | Effect |
|---|---|
| `-BLDemo YES` | Use the loopback network. A game "Quiz Night (demo)" with two players is joinable; when you host, Cleo, Dev and Eli join one by one. |
| `-BLRoute host` / `join` / `join-first` | Open straight into hosting, the Join list, or join the first game found. |
| `-BLDemoAutoPlay YES` | Your own hosted game runs rounds by itself: arm after 2 s, show results 4 s, award the winner, reset. |
| `-BLDemoAutoBuzz fast` / `early` | Press *your* buzzer for you: in 80–150 ms (you usually win) or before the buzzers open (you get locked out). |
| `-profile.name Upendra` | Skip onboarding with this name (UserDefaults argument domain). |

```sh
xcrun simctl launch --terminate-running-process booted com.upendrasharma.buzzlight \
  -profile.name Upendra -BLDemo YES -BLRoute host -BLDemoAutoPlay YES
xcrun simctl io booted screenshot host.png
```

`scripts/screenshots.sh [simulator] [dir]` builds a Debug app, warms it up and captures the six App
Store screenshots (host results, player winner, player live, host scores, join list, too early) at
the 6.9" size into `docs/app-store/screenshots/`. Waits are tuned to `DemoHub.Timing.standard`;
if you change those timings, re-check the shots.

## Manual: two or more physical devices

Simulator↔simulator MultipeerConnectivity works intermittently and simulator↔device not at all;
always verify transport changes on hardware.

Setup
1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`
   (the file is git-ignored). Run `xcodegen generate`, open the project, run on ≥ 2 iPhones.
2. All devices on the same Wi-Fi, or Wi-Fi off and Bluetooth on (peer-to-peer path).
3. On first use accept the *Local Network* permission prompt. If it was denied:
   Settings → Privacy & Security → Local Network → BuzzLight.

### Stage 2 script — discovery & lobby

| # | Steps | Expected |
|---|---|---|
| 2.1 | Fresh install on both phones | Name prompt; Continue disabled until a name is typed; name shows on Home as "Playing as …". |
| 2.2 | Phone A: Host a game | Lobby shows "A's game", A with crown and "You", "Waiting for players to join…". |
| 2.3 | Phone B: Join a game | "A's game" appears within ~3 s. |
| 2.4 | B taps the game | Spinner on the row, then "You're in!" with roster A, B. A's lobby shows B within ~1 s. |
| 2.5 | Phone C joins too (if available) | All three rosters match; header on A says "2 players". |
| 2.6 | Two phones both named "Sam" join | Both appear separately on the host. |
| 2.7 | A swipes B → Remove | B: "You were removed from the game" → Back to Home. A and C rosters drop B. |
| 2.8 | B (player) sends app to background ~10 s, returns | B shows "Reconnecting…" briefly, then the roster again; A shows B again (at the end of the list). |
| 2.8b | B sends app to background for **> 60 s**, returns | Same as 2.8 — B is *not* sent home on return (the reconnect clock pauses in the background). |
| 2.8c | B opens Control Center / app switcher and back, several times | Nothing changes; no reconnect needed. |
| 2.9 | A (host) sends app to background ~10 s, returns | Players show "Reconnecting…", then rejoin automatically once A is back. |
| 2.10 | B taps Leave | B returns Home; A's roster drops B. |
| 2.11 | A taps End → End game | Every player: "The host ended the game" → Back to Home. A returns Home. |
| 2.12 | Host force-quits (swipe up) | Players show "Reconnecting…", then after ~30 s "Lost connection to the host". |
| 2.13 | Join screen with no host for 10 s | "Looking for games…" with the Local Network hint and Open Settings button. |
| 2.14 | Wi-Fi off, Bluetooth on, both phones | 2.2–2.4 still work (slower discovery is fine). |
| 2.15 | Screen stays on in lobby | Phone doesn't auto-lock while hosting or joined. |
| 2.16 | 3+ phones join the same host within a second of each other | Everyone gets in (up to 7); no one is stuck on a spinner. |

Record results (date, devices, iOS versions, pass/fail notes) in the Stage 2 issue (#3).

### Stage 3 script — rounds (≥ 3 phones: host A, players B and C)

| # | Steps | Expected |
|---|---|---|
| 3.1 | B and C join A | A shows "Ask your question", **Arm buzzers** enabled; B and C show a grey "Get ready". |
| 3.2 | A taps Arm buzzers | B and C turn red "BUZZ!" within ~300 ms of each other (eyeball side by side). |
| 3.3 | B presses | B: buzz sound + heavy haptic, then "First!" (gold, success haptic). A: buzz sound + haptic, "B buzzed first!", B in the ranking. C still "BUZZ!" with "B buzzed first" below. |
| 3.4 | C presses | C: "#2 · +N ms". A's ranking shows C second with the same +N ms. |
| 3.5 | B and C press as close together as possible, 5 rounds | Always one winner and a Δms for the other; never a crash or a missing entry. Note the smallest Δ seen. |
| 3.6 | Before A arms, B presses | B: "Too early" (error haptic). A: "Too early: B". After Arm, B cannot buzz; C can. |
| 3.7 | A taps **+** next to the winner, then **Next round** | Points appear on A's scoreboard and on every player's points chip / Scores sheet; round number increments; buzzers open immediately. |
| 3.8 | A taps **−** | Point taken back everywhere. |
| 3.9 | A taps **Cancel round** while live, and **Reset** after results | Players return to "Get ready"; lockouts cleared. |
| 3.10 | During a live round, B backgrounds for 10 s and returns | B rejoins and shows the round's current state (still "BUZZ!" if B hadn't pressed; result if B had). |
| 3.11 | B with points taps Leave | A's scoreboard keeps B dimmed ("Left the game") with points; C's Scores sheet shows the same. |
| 3.12 | A taps End → End game | A: "Game over", winner line, final scores. B/C: "The host ended the game" with final scores. |
| 3.13 | Silent switch on / Settings → Sound effects off | No buzz sound; haptics still fire. |
| 3.14 | VoiceOver on, player | Buzzer reads "Buzzer, Live. Press to buzz."; double-tap buzzes; the winner is announced. |
| 3.15 | Screen stays on during rounds | No auto-lock on host or players. |

Record results (date, devices, iOS versions, pass/fail notes) in the Stage 3 issue (#4).

## Debugging tips

- Session logs: Console.app, subsystem `com.upendrasharma.buzzlight`, category `session`
  (failed sends, transport errors).
- `LoopbackNetwork.stop()` emits `.hostLost` then `.peerDisconnected`; a consumer expecting only
  the latter will hang on the first event.
- A transport's `events` finishes after `stop()`: a `for await` loop over it ends on its own.
- If discovery silently finds nothing on a device, check Local Network permission first, then the
  `NSBonjourServices` entries in the built Info.plist.
