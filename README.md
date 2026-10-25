# QuickBuzz

iOS buzzer game for people in the same room. Phones on the same Wi-Fi (or nearby over
Bluetooth) find each other; one person **hosts**, the others **join**; the host arms a round and
everybody smashes the buzzer — the host's phone shows who was first and by how many milliseconds.

- **v1 (free):** local play only, no account, no server.
- **Later (Plus, $0.99/year):** email account, saved and previous sessions, internet rooms.

See [`docs/roadmap.md`](docs/roadmap.md) for the staged plan and current status.

## Build

Requires Xcode 26+, Swift 6.2+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate            # creates QuickBuzz.xcodeproj (not committed)
open QuickBuzz.xcodeproj
```

Set your `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode) before running on a device.

## Test

```sh
swift test --package-path Packages/BuzzCore        # game logic, ~1 s on the Mac
swift test --package-path Packages/BuzzMultipeer
xcodebuild test -project QuickBuzz.xcodeproj -scheme QuickBuzz \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app (views only) |
| `Packages/BuzzCore` | Models, wire protocol, host/player engines, `GameTransport`, loopback transport |
| `Packages/BuzzMultipeer` | MultipeerConnectivity transport |
| `design/icon/` | App icon source; run `design/icon/make-icon.sh` (needs `librsvg`) to regenerate light/dark/tinted PNGs |
| `docs/` | [Roadmap](docs/roadmap.md) · [Architecture](docs/architecture.md) · [Protocol](docs/protocol.md) · [Testing](docs/testing.md) · [ADRs](docs/adr/) |

## License

MIT — see [LICENSE](LICENSE).
