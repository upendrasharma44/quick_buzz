# BuzzLight

iOS buzzer game for people in the same room. Phones with Wi-Fi switched on find each other
(on the same network, or directly phone to phone); one person **hosts**, the others **join**; the host arms a round and
everybody smashes the buzzer — the host's phone shows who was first and by how many milliseconds.

- **v1 (free):** local play only, no account, no server.
- **Later (Plus, $0.99/year):** email account, saved and previous sessions, internet rooms.

See [`docs/roadmap.md`](docs/roadmap.md) for the staged plan and current status.

> Formerly *QuickBuzz*: renamed before the first release ([ADR 0006](docs/adr/0006-rename-quickbuzz-to-buzzlight.md)).
> The repository keeps its original name, `quick_buzz`.

## How to play

1. Everyone opens BuzzLight on their iPhone with **Wi-Fi switched on** (same network is easiest;
   phones can also connect directly without one).
2. The quiz master taps **Host a game**; everyone else taps **Join a game** and picks it.
3. The host asks a question and taps **Arm buzzers**. Every player's button turns red.
4. First to hit **BUZZ!** wins the round. The host's phone shows the order and the gaps in
   milliseconds. Press before the buzzers open and you're locked out for that round.
5. The host awards points (**+** / **−**) and taps **Next round**. **End** shows final scores.

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
swift test --package-path Packages/BuzzNetwork
BUZZLIGHT_LIVE_NETWORK=1 swift test --package-path Packages/BuzzNetwork       # real networking, opt-in
swift test --package-path Packages/BuzzMultipeer                              # legacy transport
BUZZLIGHT_LIVE_MULTIPEER=1 swift test --package-path Packages/BuzzMultipeer   # real Multipeer, opt-in
xcodebuild test -project BuzzLight.xcodeproj -scheme BuzzLight \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app: onboarding, home, host console, join flow, buzzer, scores, settings; profile, sound and demo mode |
| `Packages/BuzzCore` | Models, wire protocol, host/player engines and sessions, `GameTransport`, loopback transport |
| `Packages/BuzzNetwork` | Network.framework transport: Bonjour discovery, TLS WebSocket connections, direct Wi-Fi |
| `Packages/BuzzMultipeer` | Legacy MultipeerConnectivity transport (DEBUG A/B only, being removed — ADR 0007) |
| `Config/` | Build settings; per-machine `Local.xcconfig` (git-ignored) |
| `design/icon/` | App icon source; run `design/icon/make-icon.sh` (needs `librsvg`) to regenerate light/dark/tinted PNGs |
| `design/sound/` | Buzzer sound source; `python3 design/sound/make-sounds.py` regenerates `App/Resources/Sounds/buzz.wav` |
| `scripts/` | `screenshots.sh`: App Store screenshots from the simulator demo · `fetch-logs.sh`: pull debug logs from phones |
| `docs/` | [Roadmap](docs/roadmap.md) · [Architecture](docs/architecture.md) · [Protocol](docs/protocol.md) · [Testing](docs/testing.md) · [Release](docs/release.md) · [App Store](docs/app-store/) · [ADRs](docs/adr/) |

App Store: _link added after approval_.

## License

MIT — see [LICENSE](LICENSE).
