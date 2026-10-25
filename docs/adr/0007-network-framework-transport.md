# ADR 0007: Network.framework transport replaces MultipeerConnectivity

- Status: Proposed — becomes Accepted when the device connectivity matrix in `docs/testing.md`
  passes rows N1–N4 (then `BuzzMultipeer` is deleted)
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
- Known limitation: a phone trying to join a full game (8th player) only gets "Couldn't join"
  after the 18 s connection expiry. Fix in Stage 4: advertise the player count in TXT and show the
  game as full in the Join list.
- When this ADR is accepted:
  - Delete `Packages/BuzzMultipeer`, the Developer transport picker's MC option, and the
    `_buzzlight-mc._tcp` / `_buzzlight-mc._udp` Bonjour entries.
  - Re-run the screenshots.
- ADR 0005's future sync frames can use a UDP `NWConnection` later if reliable delivery proves too
  slow; that was not possible with MC.
