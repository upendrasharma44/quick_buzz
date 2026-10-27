# BuzzLight — agent instructions

iOS buzzer game: nearby iPhones discover each other, one hosts, the others buzz, the host's
device ranks who buzzed first. Staged delivery; see `docs/roadmap.md` for the plan and status.

## Commands

```sh
xcodegen generate                                   # regenerate BuzzLight.xcodeproj (git-ignored)
swift test --package-path Packages/BuzzCore         # fast, pure-Swift domain + session tests (run these first)
swift test --package-path Packages/BuzzNetwork
swift test --package-path Packages/BuzzMultipeer      # legacy transport (DEBUG A/B only)
BUZZLIGHT_LIVE_NETWORK=1 swift test --package-path Packages/BuzzNetwork       # real Network.framework on this Mac
scripts/fetch-logs.sh                               # pull + merge debug logs from paired iPhones (logs/)
BUZZLIGHT_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer   # real Multipeer on this Mac
xcodebuild test -project BuzzLight.xcodeproj -scheme BuzzLight \
  -destination 'platform=iOS Simulator,name=iPhone 17' -quiet   # app + all package tests
```

Requires Xcode 26+, Swift 6.2+, `brew install xcodegen`. Device builds need
`Config/Local.xcconfig` with `DEVELOPMENT_TEAM` (git-ignored; see `Config/Local.xcconfig.example`).

Simulator demo without a second phone: launch with `-BLDemo YES` (loopback network + simulated
players), optionally `-BLRoute host|join|join-first` and `-profile.name <name>`. See `docs/testing.md`.

## Layout

- `App/` — SwiftUI app target (`BuzzLight`): views (`Features/Round` = host console, buzzer, end of game),
  `Profile`, `AppServices`, `SoundPlayer`, `DemoHub`. No game logic.
- `Packages/BuzzCore` — models, wire protocol, `GameTransport`, `HostEngine`, `PlayerEngine`,
  `HostSession`/`PlayerSession` (connection lifecycle), `LoopbackTransport`. No UIKit.
- `Packages/BuzzNetwork` — `NetworkTransport` (Network.framework → `GameTransport`; ADR 0007). The real transport.
- `Packages/BuzzMultipeer` — legacy `MultipeerTransport`, DEBUG A/B only; delete when ADR 0007 is accepted.
- `Config/` — xcconfig files; `Local.xcconfig` is per-machine and git-ignored.
- `docs/` — roadmap, architecture, protocol, testing, ADRs. **Docs are part of every change.**
- `design/icon/` — app icon source. Edit colours/shapes in `make-icon.sh` and re-run it
  (needs `brew install librsvg`); it writes the light/dark/tinted PNGs into `AppIcon.appiconset`.
  Never hand-edit the PNGs.
- `design/sound/make-sounds.py` — generates `App/Resources/Sounds/buzz.wav` (stdlib Python). Never hand-edit the WAV.
- `scripts/screenshots.sh` — App Store screenshots from demo mode; output in `docs/app-store/screenshots/`.
- `scripts/fetch-logs.sh` — fetch debug logs from paired phones and merge them into one timeline.
- `docs/app-store/`, `docs/release.md` — store metadata, review notes, privacy policy, release checklist.

## Mandatory rules

1. **Update docs with every code change.** Protocol change → `docs/protocol.md`; module/state-machine
   change → `docs/architecture.md`; finishing or re-scoping a stage → `docs/roadmap.md` status table
   and the stage's GitHub issue checklist. A design decision → new ADR in `docs/adr/`.
2. Engines (`HostEngine`, `PlayerEngine`) stay synchronous and transport-free: inputs return `[Outbound]`.
   Sessions own the async lifecycle. Never import MultipeerConnectivity or networking into `BuzzCore`.
3. Host arrival order is the only arbiter of buzz ranking. Do not introduce device-clock comparisons.
   Arrival time is the transport's `receivedAt`, not a timestamp taken on the main actor.
4. Swift 6 language mode with strict concurrency everywhere; engines and sessions are `@MainActor`.
5. Tests use Swift Testing (`import Testing`), not XCTest. Every engine or session behaviour change
   needs a test; session tests use `eventually { }` and injected short timeouts, never fixed sleeps.
6. Never commit `*.xcodeproj`, `App/Info.plist` or `Config/Local.xcconfig`; `project.yml` is the source of truth.
7. Work on a branch per stage (`stage-N-<slug>`), open a PR, and link the stage issue.

## Known pitfalls

- Device problems are debugged from logs, not guesses: phones record with Settings → Diagnostics (or
  `-BLDebugLog YES`), `scripts/fetch-logs.sh` pulls them. When adding session or transport behaviour,
  add `debugLog(.session/.transport, …)` lines for its decisions and failures.

- Phones need **Wi-Fi switched on**; a shared network isn't required with `NetworkTransport`
  (`includePeerToPeer`). Nothing in the app may claim Bluetooth play: MultipeerConnectivity hasn't used
  Bluetooth since iOS 11, and Network.framework doesn't either.
- `NetworkTransport` receive loop: a WebSocket close frame or `context.isFinal` must cancel the connection;
  otherwise `receiveMessage` completes empty forever and disconnects surface only via keepalive (~7 s).
  Live test `discoverConnectExchangeAndDisconnect` asserts < 3 s.
- Peer-to-peer Wi-Fi (`awdl0`) stays up on a phone only while it browses or advertises: never stop
  the player's browser while its connection is over `awdl*` (`NetworkTransport.stopBrowsing` checks).
  Don't make TCP keepalive aggressive; liveness is the sessions' 1 s heartbeat (10–12 s silence).
- `NetworkTransport` and `MultipeerTransport` use different Bonjour types (`_buzzlight._tcp` vs
  `_buzzlight-mc._tcp`); every phone in a game must use the same transport (DEBUG Settings → Developer).

- The buzzer must act on **touch-down** and call `PlayerSession.buzz()` synchronously in the gesture
  callback (no `Task`/`await` first); sound and anything else come after. ADR 0005 will stamp the press
  there in Stage 4.
- Release identifiers are now BuzzLight's (ADR 0006): bundle ID `com.upendrasharma.buzzlight`, service
  type `buzzlight`. After the first App Store release neither may change.
- Version numbers live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`); Info.plist
  reads them. Every App Store upload needs a higher `CURRENT_PROJECT_VERSION`.

- Multipeer discovery silently fails without `NSLocalNetworkUsageDescription` and `NSBonjourServices`
  (`_buzzlight._tcp`, `_buzzlight._udp`) in Info.plist — they are set in `project.yml`.
- Simulator↔simulator Multipeer is unreliable; test transport changes on two physical devices
  (`docs/testing.md`). Use `LoopbackTransport` for previews and automated tests.
- MultipeerConnectivity calls delegates on private queues. In `MultipeerTransport`, mutate state and
  yield events only under `lock`, and never call an MC API while holding it.
- `MCPeerID` display names must be 1–63 UTF-8 bytes (`PeerName.sanitized`); an `MCSession` holds 8 peers,
  so a host accepts at most 7 players. MC cannot disconnect one peer: kicked players leave on their own.
- MC silently drops an invitation sent through a browser that hasn't reported that peer yet. Never
  replace a running browser/advertiser (MC resumes them after backgrounding by itself); invitations
  are deferred until the current browser finds the host and expire on their own. Live regression test:
  `inviteThroughAFreshBrowserIsDeferredUntilFound`.
- An MC session is a full mesh: players are linked to each other too. Players must address the host
  explicitly; never `broadcast` from a player.
- `Task.sleep` keeps counting while the app is suspended; foreground-only deadlines need scene-phase hooks.
- A transport's `events` stream finishes after `stop()`. `LoopbackNetwork.stop()` emits `.hostLost`
  before `.peerDisconnected`; consumers must handle both.
- XcodeGen does not set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` by default; it is set in
  `project.yml` so `AccentColor` tints the app.
- Inside a `List` row `Button`, `.foregroundStyle(.primary)` resolves to the tint; use `Color.primary`.
