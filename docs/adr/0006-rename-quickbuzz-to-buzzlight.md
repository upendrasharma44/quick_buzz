# ADR 0006: Rename the app from QuickBuzz to BuzzLight before the first release

- Status: Accepted
- Date: 2026-10-25
- Decision makers: @upendrasharma44

## Context

The product owner wants to ship the app as **BuzzLight** instead of QuickBuzz. Nothing has been
released or submitted yet: there is no App Store Connect record, no TestFlight build, and no player
has the app installed. Some identifiers can never change once a version ships: the bundle ID is
permanent in App Store Connect, and the Bonjour service type must match between every version that
should be able to play together.

## Decision

Rename everything that carries the product name now, while it is free:

| Item | Before | After |
|---|---|---|
| Display name / App Store name | QuickBuzz | BuzzLight |
| Bundle ID | `com.upendrasharma.quickbuzz` | `com.upendrasharma.buzzlight` |
| Multipeer service type / `NSBonjourServices` | `quickbuzz` / `_quickbuzz._tcp`, `_quickbuzz._udp` | `buzzlight` / `_buzzlight._tcp`, `_buzzlight._udp` |
| Xcode project, app target, scheme | `QuickBuzz` (`QuickBuzz.xcodeproj`) | `BuzzLight` (`BuzzLight.xcodeproj`) |
| App test target / module | `QuickBuzzTests`, `@testable import QuickBuzz` | `BuzzLightTests`, `@testable import BuzzLight` |
| Log subsystem | `com.upendrasharma.quickbuzz` | `com.upendrasharma.buzzlight` |
| DEBUG launch arguments | `-QBDemo`, `-QBRoute`, `-QBDemoAutoPlay`, `-QBDemoAutoBuzz` | `-BLDemo`, `-BLRoute`, `-BLDemoAutoPlay`, `-BLDemoAutoBuzz` |
| Live-test switch | `QUICKBUZZ_LIVE_MULTIPEER` | `BUZZLIGHT_LIVE_MULTIPEER` |

Kept as they are: the GitHub repository `upendrasharma44/quick_buzz` (renaming it is a separate,
outward-facing step; GitHub redirects the old URL if it is ever renamed), the Swift packages
`BuzzCore` / `BuzzMultipeer` (no product name in them), and ADRs 0001–0002, which describe
decisions as they were made.

## Consequences

- Builds with the old bundle ID on test devices or simulators are a different app; delete them.
  `UserDefaults` (display name, player ID) does not carry over — there are no real users yet.
- Old and new builds cannot discover each other (different service type). Acceptable before release.
- An App ID `com.upendrasharma.quickbuzz` may exist in the developer account if a device build was
  made earlier; it is unused and can be deleted at developer.apple.com.
- App Store name availability is only confirmed when the App Store Connect record is created;
  fallbacks are listed in `docs/app-store/metadata.md`.
