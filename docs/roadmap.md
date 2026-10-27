# Roadmap

The plan for BuzzLight, executed one stage at a time. Each stage has a GitHub milestone and a
tracking issue whose checklist is the authoritative task list. **Update the status table here
and tick the issue checklist whenever a stage changes state.**

How to work a stage: read this file and the stage issue → branch `stage-N-<slug>` → implement with
tests and docs → PR referencing the issue → merge → update status → close issue + milestone.

## Status

| Stage | Title | Issue | Status | Release |
|---|---|---|---|---|
| 0 | Scaffold & plan tracking | [#1](https://github.com/upendrasharma44/quick_buzz/issues/1) | ✅ Done (2026-10-25) | — |
| 1 | Domain core (engines, protocol, loopback) | [#2](https://github.com/upendrasharma44/quick_buzz/issues/2) | ✅ Done (2026-10-25) | — |
| 2 | Discovery & lobby over Multipeer | [#3](https://github.com/upendrasharma44/quick_buzz/issues/3) | 🔧 Transport replaced (ADR 0007); awaiting device connectivity matrix | v0.2 (dev) |
| 3 | Buzz rounds | [#4](https://github.com/upendrasharma44/quick_buzz/issues/4) | 🔧 Built; awaiting 3-phone test + App Store submission | **v1.0 free** |
| 4 | Robustness & fairness polish | [#5](https://github.com/upendrasharma44/quick_buzz/issues/5) | ⬜ Not started | v1.x |
| 5 | Plus tier (StoreKit 2, $0.99/yr) | [#6](https://github.com/upendrasharma44/quick_buzz/issues/6) | ⬜ Not started | v1.2 |
| 6 | Accounts & session history (Firebase) | [#7](https://github.com/upendrasharma44/quick_buzz/issues/7) | ⬜ Not started | v2.0 |
| 7 | Internet rooms & other transports | [#8](https://github.com/upendrasharma44/quick_buzz/issues/8) | ⬜ Not started | v2.x |

Legend: ⬜ not started · 🔧 in progress · ✅ done · ⏸ paused

## Product

Several iPhones in one room discover each other over the local network. Each user has a display
name. One user becomes the **host** (coordinator); the others **join** as players. The host arms a
round, players buzz, and the host's device — the single source of truth — shows who buzzed first
and the full ranking with millisecond deltas.

Delivery is free-first: v1 has no server, no account and no purchase. Later versions add a
$0.99/year "Plus" subscription that unlocks an email-based account, saved and previous sessions,
and internet rooms.

### Free vs Plus

| Capability | Free | Plus ($0.99 / year) |
|---|---|---|
| Local play (same Wi-Fi network, or direct phone-to-phone Wi-Fi) | ✅ unlimited | ✅ |
| Display name, in-session scores | ✅ | ✅ |
| Email account | — | ✅ (Stage 6) |
| Saved sessions, previous sessions, round history | — | ✅ (Stage 6) |
| Internet rooms by code / QR | — | ✅ (Stage 7) |
| Team mode, custom buzz sounds / themes | — | ✅ (backlog) |

### Fairness rules (fixed in Stage 1, see `docs/architecture.md`)

- Ranking = order buzzes arrive at the host; deltas from a monotonic host clock. Device clocks are never compared.
- Stale-round buzzes ignored; duplicates dropped; a buzz before the round is armed locks that player out for the round.
- Stage 4 adds RTT confidence and an optional tie threshold; the host remains authoritative.
  Proposed design: per-player clock-offset estimation and local press timestamps,
  arrival order kept as fallback (`docs/adr/0005-clock-offset-press-timestamp-ranking.md`).

## Stages

### Stage 0 — Scaffold & plan tracking ✅
XcodeGen project (iOS 18, Swift 6 strict concurrency), local packages `BuzzCore` and
`BuzzMultipeer`, placeholder app, CI, docs set (this file, architecture, protocol, testing, ADRs
0001–0003), `CLAUDE.md`, GitHub labels/milestones/issues.

### Stage 1 — Domain core ✅
`BuzzCore`: models, versioned `GameMessage` codec, `GameTransport` contract, `LoopbackTransport`,
`HostEngine` (arbitration state machine) and `PlayerEngine`, 34 Swift Testing tests including a
host + 2 players loopback round. No UI, no networking.

### Stage 2 — Discovery & lobby over Multipeer 🔧
Built on 2026-10-25; the stage closes once the two-phone script in `docs/testing.md` passes.
- `MultipeerTransport`: advertiser/browser/session, auto-accept up to 7 players, peer registry,
  arrival timestamps, version-mismatch detection. Verified against real MultipeerConnectivity by
  the opt-in live tests.
- `HostSession` / `PlayerSession` in `BuzzCore`: join, 20 s connect timeout, automatic reconnect
  (30 s of foreground time) after a drop, kick, leave, host end, version checks (ADR 0004).
- Independent review against real MultipeerConnectivity found 4 defects (dropped invitations after a
  browser restart, mesh-wide version errors, reconnect clock running while suspended, player cap
  race); all fixed with regression tests.
- App: name onboarding + persisted `PlayerID`, Home, Host lobby (live roster, kick, end), Join
  browser (nearby games, Local Network hint), player waiting screen, end screens, Settings
  (rename), keep-awake during games, DEBUG demo mode with simulated players.
- Device test (2026-10-25): Multipeer only connected phones on the same Wi-Fi network; Bluetooth-only
  never works (MC dropped Bluetooth in iOS 11). Replaced by a Network.framework transport with direct
  peer-to-peer Wi-Fi (ADR 0007, package `BuzzNetwork`); Multipeer kept for DEBUG A/B only.
- Remaining: the connectivity matrix and two-phone script in `docs/testing.md` on hardware, results in #3.

### Stage 3 — Buzz rounds → v1.0 free release 🔧
Built on 2026-10-25 (ranking stays host arrival order; ADR 0005 follows in Stage 4 by decision).
- Host console (it is also the lobby): Arm / Cancel / Reset / Next round / End, live ranking with Δms,
  lockouts, ±1 awards, scoreboard with kick, buzz sound + haptic on the first buzz.
- Player buzzer firing on touch-down, with sound, haptics and VoiceOver; points chip, round caption,
  scores sheet; final standings for everyone when the game ends.
- Session API (`arm`, `reset`, `nextRound`, `award`, `buzz`), name cache for departed players,
  `Standings`; demo mode plays real rounds; `scripts/screenshots.sh`.
- App renamed **QuickBuzz → BuzzLight** before release (ADR 0006).
- Release prep: v1.0.0 (1), iPhone-only, launch screen, export-compliance flag,
  `docs/app-store/` (metadata, review notes, privacy policy, screenshots), `docs/release.md`.
- App icon (2026-10-25, BuzzLight redesign): buzzer + lightning bolt circled by an orbit ring with a satellite orb over a starfield, light/dark/tinted, from `design/icon/make-icon.sh` (concept in `design/icon/README.md`).
- Remaining (owner): 3-phone script in `docs/testing.md`, App Store Connect record, TestFlight,
  submission, then tag `v1.0.0` — see `docs/release.md`.

### Stage 4 — Robustness & fairness polish (v1.x)
RTT estimation and confidence display, optional tie threshold (design proposed in ADR 0005:
clock-offset estimation + local press timestamps, host still the only arbiter), host approval /
session PIN, duplicate-name handling, host handoff spike, accessibility, localization scaffold,
iPad layout.

### Stage 5 — Plus tier (StoreKit 2)
`BuzzStore` package: `plus.yearly` auto-renewable subscription at $0.99/yr, entitlement object
injected app-wide, paywall, restore, StoreKit configuration for local tests, App Review compliance.

### Stage 6 — Accounts & session history (Firebase)
`BuzzCloud` package: Firebase Auth (email/password, email link), Firestore `users` / `sessions`,
security rules, Cloud Function verifying App Store subscription, `SessionStore` protocol with
local (SwiftData) and cloud implementations, Previous sessions UI, account deletion.

### Stage 7 — Internet rooms & other transports
`BuzzRelay` package: `GameTransport` over Firebase Realtime Database (or a WebSocket relay after a
latency spike), room code / QR join, transport picker (Nearby free / Online Plus), Bluetooth-only nearby play would need a Core Bluetooth transport (Multipeer dropped
Bluetooth in iOS 11; ADR 0007).

## Backlog (unscheduled)
- Team mode (buzz on behalf of a team, team scores)
- Custom buzz sounds and themes (Plus)
- Apple Watch buzzer companion
- Android client over the relay transport (protocol is JSON; see `docs/protocol.md`)
