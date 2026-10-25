# QuickBuzz — agent instructions

iOS buzzer game: nearby iPhones discover each other, one hosts, the others buzz, the host's
device ranks who buzzed first. Staged delivery; see `docs/roadmap.md` for the plan and status.

## Commands

```sh
xcodegen generate                                   # regenerate QuickBuzz.xcodeproj (git-ignored)
swift test --package-path Packages/BuzzCore         # fast, pure-Swift domain tests (run these first)
swift test --package-path Packages/BuzzMultipeer
xcodebuild test -project QuickBuzz.xcodeproj -scheme QuickBuzz \
  -destination 'platform=iOS Simulator,name=iPhone 17' -quiet   # app + all package tests
```

Requires Xcode 26+, Swift 6.2+, `brew install xcodegen`.

## Layout

- `App/` — SwiftUI app target (`QuickBuzz`). Views only; no game logic.
- `Packages/BuzzCore` — models, wire protocol, `GameTransport`, `HostEngine`, `PlayerEngine`, `LoopbackTransport`. No UIKit.
- `Packages/BuzzMultipeer` — `MultipeerTransport` (MultipeerConnectivity → `GameTransport`).
- `docs/` — roadmap, architecture, protocol, testing, ADRs. **Docs are part of every change.**

## Mandatory rules

1. **Update docs with every code change.** Protocol change → `docs/protocol.md`; module/state-machine
   change → `docs/architecture.md`; finishing or re-scoping a stage → `docs/roadmap.md` status table
   and the stage's GitHub issue checklist. A design decision → new ADR in `docs/adr/`.
2. Engines (`HostEngine`, `PlayerEngine`) stay synchronous and transport-free: inputs return `[Outbound]`.
   Never import MultipeerConnectivity or networking into `BuzzCore`.
3. Host arrival order is the only arbiter of buzz ranking. Do not introduce device-clock comparisons.
4. Swift 6 language mode with strict concurrency everywhere; engines are `@MainActor`.
5. Tests use Swift Testing (`import Testing`), not XCTest. Every engine behaviour change needs a test.
6. Never commit `*.xcodeproj`; `project.yml` is the source of truth.
7. Work on a branch per stage (`stage-N-<slug>`), open a PR, and link the stage issue.

## Known pitfalls

- Multipeer discovery silently fails without `NSLocalNetworkUsageDescription` and `NSBonjourServices`
  (`_quickbuzz._tcp`, `_quickbuzz._udp`) in Info.plist — they are set in `project.yml`.
- Simulator↔simulator Multipeer is unreliable; test transport changes on two physical devices
  (`docs/testing.md`). Use `LoopbackTransport` for previews and automated tests.
- `LoopbackNetwork.stop()` emits `.hostLost` before `.peerDisconnected`; consumers must handle both.
