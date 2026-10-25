# BuzzLight

iOS buzzer game for people in the same room. Phones on the same Wi-Fi (or nearby over
Bluetooth) find each other; one person **hosts**, the others **join**; the host arms a round and
everybody smashes the buzzer — the host's phone shows who was first and by how many milliseconds.

- **v1 (free):** local play only, no account, no server.
- **Later (Plus, $0.99/year):** email account, saved and previous sessions, internet rooms.

See [`docs/roadmap.md`](docs/roadmap.md) for the staged plan and current status.

> Formerly *QuickBuzz*: renamed before the first release ([ADR 0006](docs/adr/0006-rename-quickbuzz-to-buzzlight.md)).
> The repository keeps its original name, `quick_buzz`.

## Build

Requires Xcode 26+, Swift 6.2+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate            # creates BuzzLight.xcodeproj (not committed)
open BuzzLight.xcodeproj
```

To run on an iPhone, create `Config/Local.xcconfig` (git-ignored) from
`Config/Local.xcconfig.example` with your `DEVELOPMENT_TEAM`, then re-run `xcodegen generate`.

No second phone handy? In a DEBUG build, launch with `-BLDemo YES` for a simulated network with
pretend players (details in [`docs/testing.md`](docs/testing.md#demo-mode-simulator-debug-builds)).

## Test

```sh
swift test --package-path Packages/BuzzCore        # game logic + sessions, ~1 s on the Mac
swift test --package-path Packages/BuzzMultipeer
BUZZLIGHT_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer   # real Multipeer, opt-in
xcodebuild test -project BuzzLight.xcodeproj -scheme BuzzLight \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app: onboarding, home, host lobby, join flow, settings; profile and demo mode |
| `Packages/BuzzCore` | Models, wire protocol, host/player engines and sessions, `GameTransport`, loopback transport |
| `Packages/BuzzMultipeer` | MultipeerConnectivity transport |
| `Config/` | Build settings; per-machine `Local.xcconfig` (git-ignored) |
| `design/icon/` | App icon source; run `design/icon/make-icon.sh` (needs `librsvg`) to regenerate light/dark/tinted PNGs |
| `docs/` | [Roadmap](docs/roadmap.md) · [Architecture](docs/architecture.md) · [Protocol](docs/protocol.md) · [Testing](docs/testing.md) · [ADRs](docs/adr/) |

## License

MIT — see [LICENSE](LICENSE).
