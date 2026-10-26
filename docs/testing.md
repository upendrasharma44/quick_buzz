# Testing

## Automated

| Layer | Command | What it covers |
|---|---|---|
| Domain + sessions | `swift test --package-path Packages/BuzzCore` | 72 tests. Protocol round trips; `HostEngine` arbitration; `PlayerEngine` statuses; loopback contract; `HostSession`/`PlayerSession` over `LoopbackTransport` (discovery, join, same-name players, failed and timed-out joins, leave, kick, host end, host crash → connection lost, drop → reconnect with score kept) and over `ScriptedTransport` (player traffic goes to the host only, mesh frames and other peers' version errors ignored, incompatible hosts not joinable, reconnect deadline paused in background, late link usable on retry); full rounds through sessions (arm → buzz order → results everywhere → award → next round, early-press lockout, repeated taps, reconnect mid-round, departed names for late joiners); `Standings`. ~0.5 s. |
| Transport (Network.framework) | `swift test --package-path Packages/BuzzNetwork` | 11 tests: Bonjour service type, player limit, connection expiry ordering, parameters (peer-to-peer on; WebSocket over TLS over TCP; noDelay + keepalive), PSK size, TXT round trip, error paths, `stop()` semantics. |
| Transport, live (Network.framework) | `BUZZLIGHT_LIVE_NETWORK=1 swift test --package-path Packages/BuzzNetwork` | **Real Network.framework** on this Mac: discover → connect → messages both ways → host stop noticed **within 3 s**; connect right after a browser restart; 8th player refused; frame from another protocol version gets the player turned away; reconnect after a drop; full `HostSession`/`PlayerSession` round. ~25 s (the refusal waits out the 18 s expiry). Opt-in; not in CI. |
| Transport (legacy Multipeer) | `swift test --package-path Packages/BuzzMultipeer` | Service type, player cap, invitation timeout/expiry ordering, version checks (discovery info + invitation context), `PeerRegistry`, display-name sanitising, discovery-info limits, send/connect error paths, `stop()` semantics. |
| Transport, live (legacy Multipeer) | `BUZZLIGHT_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer` | **Real MultipeerConnectivity** between two transports on this Mac: discover → invite → connect → messages both ways → disconnect; invitation through a fresh browser (regression: fails in ~20 s without the deferral, passes in ~1 s with it); the full `HostSession`/`PlayerSession` stack joining, syncing the roster and ending. ~5 s. Opt-in (needs the local network); not run in CI. macOS may ask for Local Network permission for your terminal the first time. |
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
2. Wi-Fi **switched on** on every phone. Which network (if any) each phone joins is what the
   connectivity matrix below varies.
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
| 2.14 | Wi-Fi switched off on the player | The game does not appear (or can't be joined); after 8 s the Join screen shows the "make sure Wi-Fi is switched on" hint. Bluetooth alone is not supported. |
| 2.15 | Screen stays on in lobby | Phone doesn't auto-lock while hosting or joined. |
| 2.16 | 3+ phones join the same host within a second of each other | Everyone gets in (up to 7); no one is stuck on a spinner. |

Record results (date, devices, iOS versions, pass/fail notes) in the Stage 2 issue (#3).

### Connectivity matrix — run with **each** transport

Switch the transport in **Settings → Developer → Transport** (DEBUG builds from Xcode) on *every*
phone; all phones in a game must use the same one. Host = phone A on home Wi-Fi throughout.
For each row: does B see A's game, does B join, does a round work (arm → buzz → result)?

| Row | Player B's setup | Network.framework (expected) | Multipeer (observed 2026-10-25) |
|---|---|---|---|
| N1 | Same Wi-Fi as A | Join + round work | Works |
| N2 | A *different* Wi-Fi network | Join + round work (direct Wi-Fi) | Sees game, can't join |
| N3 | Wi-Fi on but not joined to any network, mobile data **off** | Join + round work (direct Wi-Fi) | Sees game, can't join |
| N4 | Wi-Fi on, not joined, mobile data **on** | Join + round work | Sees game, spinner, "Couldn't join" (iOS 26 MC bug) |
| N5 | Wi-Fi switched off (Settings) | Can't join; hint shown | Sees game, spinner, "Couldn't join" |

Also note for N2–N4: time from tapping the game to "You're in!", and whether buzz results feel
instant. Record the filled-in matrix (device models, iOS versions) in issue #3. If Network.framework
passes N1–N4, ADR 0007 is accepted and Multipeer is deleted.

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

## Debug log (devices)

Opt-in trace of what each phone does, written by `DebugLog` (BuzzCore) to
`Library/Application Support/DebugLog/debug.log` in the app container (rotates at 2 MB, previous
kept as `debug.log.1`). Each line has the wall-clock time (to align phones), seconds since launch,
a category (`app`, `session`, `transport`) and a message:

```
2026-10-25T19:00:10.889-04:00 +1.112s [session] player buzz pressed: status ready → buzzed, round #1 armed, sending
2026-10-25T19:00:10.890-04:00 +1.113s [session] host ← message buzz(#1) from player#1
```

What is logged:
- **Sessions:** start, phase changes, every transport event handled, every message sent, send
  failures, buzz presses (with status before/after), timeouts, reconnect attempts, scene changes.
- **Transport:** listener and browser states, Bonjour registration, browse results with interfaces,
  every connection state change with the network path (`en0:wifi` = joined network, `awdl0:wifi` =
  direct peer-to-peer Wi-Fi), viability and better-path changes, slow (> 200 ms) or failed sends,
  receive errors, close frames, expiries, refusals.
- **App:** a header per launch (build, phone model, iOS, player, transport), scene phase, which
  transport each game uses.

**Record:** builds installed from Xcode (DEBUG) record by default; check Settings → Diagnostics →
**Record debug log** is on for *every* phone (release builds: turn it on there, or launch with
`-BLDebugLog YES`). Then reproduce the problem and note roughly when it happened.

**Fetch:**
- Phones paired with this Mac (USB, or same network with "Connect via network"), app installed from
  Xcode: `scripts/fetch-logs.sh` (all reachable phones) or `scripts/fetch-logs.sh "Aadi’s iphone"`.
  It writes `logs/<timestamp>/<phone>/debug.log` plus `merged.log`, all phones' lines in one
  wall-clock timeline (`logs/` is git-ignored).
- From any phone: Settings → Diagnostics → **Share debug log** (AirDrop it to the Mac).
- Live while plugged in: Console.app, filter subsystem `com.upendrasharma.buzzlight`, category `debug`.
- Simulator: `"$(xcrun simctl get_app_container booted com.upendrasharma.buzzlight data)/Library/Application Support/DebugLog/debug.log"`.
- Mac live tests: `BUZZLIGHT_LIVE_NETWORK=1 BUZZLIGHT_TRACE=1 swift test --package-path Packages/BuzzNetwork --filter sessionsJoinPlayARoundAndEnd` prints a full trace.

Clear it (Settings → Diagnostics → Clear debug log) before a new test so the files stay short.

What healthy and broken peer-to-peer play look like in the merged log:
- Healthy: the player's join is followed by `keeping the browser running: connected over
  peer-to-peer Wi-Fi ["awdl0"]`, then `host rtt Aadi: min … / avg … / max … ms` every ~10 s, and
  buzzes show up on both sides within tens of milliseconds.
- Broken (fixed 2026-10-25): `browser state cancelled` right after `→ joined`, then sends with no
  matching `←` on the other phone, and both sides failing with `Operation timed out` within the
  same ~30 ms.
- Silence handling: `host: Aadi silent for …; dropping the link` or `player: host silent for …;
  dropping the link`, followed by a reconnect. `player re-sending a buzz the host never got` means a
  press survived a drop.

## Debugging tips

- Session logs: Console.app, subsystem `com.upendrasharma.buzzlight`, category `session`
  (failed sends, transport errors).
- `LoopbackNetwork.stop()` emits `.hostLost` then `.peerDisconnected`; a consumer expecting only
  the latter will hang on the first event.
- A transport's `events` finishes after `stop()`: a `for await` loop over it ends on its own.
- If discovery silently finds nothing on a device, check Local Network permission first, then the
  `NSBonjourServices` entries in the built Info.plist.
