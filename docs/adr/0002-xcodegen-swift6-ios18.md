# ADR 0002: XcodeGen project, Swift 6 strict concurrency, iOS 18 minimum, local packages

- Status: Accepted
- Date: 2026-10-25

## Context

A fresh repo needs a reproducible Xcode project, a module structure that keeps game logic
testable without the simulator, and a concurrency story that will not need a rewrite later.

## Decision

- **XcodeGen** (`project.yml`) generates `QuickBuzz.xcodeproj`; the project file is git-ignored.
- **iOS 18.0** minimum, **Swift 6 language mode** with `SWIFT_STRICT_CONCURRENCY=complete`
  everywhere.
- Logic lives in **local Swift packages** (`Packages/BuzzCore`, `Packages/BuzzMultipeer`, more
  later) that also declare `macOS 15` so `swift test` runs natively on the Mac and in CI without a
  simulator.
- **Swift Testing** for all tests; SwiftUI + Observation (`@Observable`) for UI state.

## Alternatives considered

- Committed `.xcodeproj` — merge conflicts and opaque diffs; fine for one person, bad for agents.
- Tuist — more features than needed; heavier toolchain.
- iOS 17 — would keep ~5 % more devices but lose nothing essential; the user chose 18.
- Single app target with folders — faster to start, but engine tests would need the simulator and
  the transport boundary would erode.

## Consequences

- `brew install xcodegen` is a setup step (also in CI).
- Anyone changing targets or plist keys edits `project.yml`, never Xcode's UI.
- Strict concurrency forces explicit actor isolation now (`@MainActor` engines, `Sendable`
  transports), avoiding a Swift 6 migration later.
- `swift test --package-path Packages/BuzzCore` is the inner loop (~1 s).
