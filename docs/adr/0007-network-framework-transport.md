# ADR 0007: Network.framework transport replaces MultipeerConnectivity

- Status: **Accepted** (2026-10-27): the device connectivity matrix in `docs/testing.md` passed
  N1–N5 (iPhone 14 host, iPhone 12 player, iOS 27). `BuzzMultipeer` deleted the same day.
- Date: 2026-10-25
- Decision makers: @upendrasharma44
- Supersedes: [ADR 0001](0001-multipeer-transport-for-v1.md)

## Context

Device testing showed MultipeerConnectivity (ADR 0001) only connects phones that are on the
**same Wi-Fi network**. Players with Wi-Fi off, or with Wi-Fi on but not on the host's network
(with or without mobile data), saw the game but could not join: a spinner, then "Couldn't join".

Apple's position, from DTS on the developer forums:
- MC has not used Bluetooth since iOS 11. Peer-to-peer support is now peer-to-peer Wi-Fi only.
- On iOS 26, MC can hang in `.connecting` when Wi-Fi isn't joined to a network. Apple calls this a
  bug, with no workaround.
- MC should be treated as deprecated: "don't use it for new code". Apps should move to
  Network.framework, which TN3213 ("Moving from Multipeer Connectivity to Network Framework")
  describes.

Nothing has shipped, so changing transports now costs no compatibility.

## Decision

Implement `NetworkTransport` (package `BuzzNetwork`) behind the existing `GameTransport` contract,
following TN3213's recommended recipe:

| Concern | Choice |
|---|---|
| Discovery | Host: `NWListener` advertising Bonjour `_buzzlight._tcp` with TXT `session`, `v`. Players: `NWBrowser(.bonjourWithTXTRecord)`. |
| Topology | Star: one `NWConnection` per player, to the host only. No session mesh. |
| Direct connections | `includePeerToPeer = true` on listener, browser and connections: phones with Wi-Fi switched on can connect without sharing a network. |
| Framing | WebSocket binary messages, one `GameMessageCodec` envelope each. Wire messages are unchanged (protocol v1). |
| Security | TLS-PSK (`TLS_PSK_WITH_AES_128_GCM_SHA256`) with an app-wide key derived from a constant. |
| Latency | `TCP_NODELAY`, so small frames go out immediately. Keepalive notices vanished peers. |
| Version gate | Players grey out hosts whose TXT `v` differs. The host closes a connection whose frame has another version. |

`MultipeerTransport` stays only for DEBUG A/B testing (Settings → Developer → Transport, or
`-BLTransport multipeer`), under a separate service type (`buzzlight-mc`) so the two never
discover each other. Release builds always use Network.framework.

## Alternatives considered

- **Keep MC, require the same Wi-Fi network.** Fastest to ship, but it rests on a framework Apple
  says not to use, and it fails exactly where a "phones in a room" game is most needed (no shared
  Wi-Fi).
- **Core Bluetooth transport.** The only way to play with Wi-Fi off. It means a custom
  GATT protocol, lower throughput and more code. Turning Wi-Fi on is a one-tap fix for players, so
  this is deferred (Stage 7, "other transports").
- **Wi-Fi Aware (iOS 26).** Requires iOS 26 (the minimum is iOS 18) and new entitlements.
  Worth re-checking in Stage 7.
- **TLS with certificates, or no encryption.** Certificates need provisioning that a local party
  game can't do. Plain TCP would be simplest, but TLS-PSK costs one handshake and keeps frames
  private from other apps on the network.
- **Custom `NWProtocolFramer`** instead of WebSocket. More code for the same message boundaries.

## Consequences

- Wi-Fi must be **switched on** on every phone. A shared network is no longer required (to be
  confirmed on devices, matrix rows N2–N3). Wi-Fi off still can't work. App and store text say so.
- The TLS-PSK key ships in the app, so it encrypts but does not authenticate players: a modified
  client can still join. That's acceptable for a local game; a per-game PIN (Stage 4 "session PIN")
  could later feed the key.
- Export compliance is unchanged: encryption comes only from Apple's built-in TLS, which is exempt
  (`ITSAppUsesNonExemptEncryption = NO`).
- Lessons kept from the MC work:
  - The same lock discipline and event ordering.
  - Pending connections expire.
  - Callbacks from replaced objects are ignored.
  - A WebSocket close frame or end of stream cancels the connection at once. Without that, the
    receive loop spins until keepalive (~7 s). A live test asserts the disconnect is seen within 3 s.
- **Device findings (2026-10-25, debug logs from both phones).** Host on Wi-Fi, player off it:
  the player found and joined the game over peer-to-peer Wi-Fi (`awdl0`), but in 6 of 6
  connections traffic stopped 2–3 s after joining. Buzzes and `armed` were lost, and TCP
  keepalive then killed both ends at the same moment ("Operation timed out"). Each time, the
  player's browser had been stopped 1–2 ms after joining, and every browser restart brought the
  link straight back. iOS keeps AWDL up on a phone only while something there browses or
  advertises. Changes:
  - `NetworkTransport.stopBrowsing()` keeps the browser running while a connection uses
    peer-to-peer Wi-Fi (`awdl*`/`llw*`). It still stops on infrastructure Wi-Fi, where an
    active browse would make the radio hop channels and add jitter.
  - The sessions send a 1 s heartbeat (`ping`/`pong`, already in protocol v1). Both sides drop a
    link after 10–12 s of silence (`GameTransport.disconnect(_:)`), so neither side keeps
    sending into a connection only it believes in. Round-trip times go to the debug log.
  - TCP keepalive relaxed from ~11 s to ~30 s, as a last resort only.
  - A buzz the host never ranked is re-sent after a reconnect if the round is still open
    (`PlayerEngine.unconfirmedBuzz`).
  - Apple confirms peer-to-peer Wi-Fi has inherent stalls when one phone is also on
    infrastructure Wi-Fi, with no API to raise it to low-latency mode (forums 819926). Wi-Fi
    Aware (iOS 26+) has a realtime mode, worth evaluating in Stage 7.
- Known limitation: a phone trying to join a full game (8th player) only gets "Couldn't join"
  after the 18 s connection expiry. Fix in Stage 4: advertise the player count in TXT and show the
  game as full in the Join list.
- On acceptance (done 2026-10-27):
  - `Packages/BuzzMultipeer`, the DEBUG Developer → Transport picker (`TransportKind`,
    `-BLTransport`) and the `_buzzlight-mc._tcp/_udp` Bonjour entries were deleted.
  - App Store screenshots unchanged: none of the captured screens changed.
- ADR 0005's future sync frames can use a UDP `NWConnection` later if reliable delivery proves too
  slow; that was not possible with MC.
