# Wire protocol

Source of truth: `Packages/BuzzCore/Sources/BuzzCore/Protocol.swift`. Round-trip tests:
`Tests/BuzzCoreTests/ProtocolTests.swift`.

## Envelope

Every frame is one JSON object produced by `GameMessageCodec`:

```json
{ "version": 1, "message": { "<case>": { ...payload } } }
```

- `version` — `Envelope.currentVersion`, currently **1**. A receiver that gets a different version
  throws `ProtocolError.unsupportedVersion`; `MultipeerTransport` turns that into
  `.failed(.incompatibleVersion(v, from: peer))`. A player's session ends with "Different app
  versions" only if that peer is its host; the host shows an inline notice.
- `message` — Swift `Codable` synthesized enum encoding: the case name is the single key; cases
  without payload encode as `{ "kick": {} }`.
- Keys are sorted for stable output. Messages are small (< 2 KB); Multipeer sends them as
  `.reliable` data frames.

## Discovery and transport (Network.framework, ADR 0007)

Before any frame is exchanged, players find hosts through Bonjour:

| Item | Value |
|---|---|
| Service type | `_buzzlight._tcp` (Info.plist `NSBonjourServices`) |
| Who advertises | Host only (`NWListener`). Players browse (`NWBrowser`) and open one connection to the host. |
| Instance name | The session name, ≤ 63 UTF-8 bytes (Bonjour renames duplicates, e.g. "Sam's game (2)"). |
| TXT record | `session` → session name shown in the Join list (≤ 120 bytes, default "<name>'s game"); `v` → `Envelope.currentVersion` |
| Topology | Star: players are connected to the host only. |
| Links | Same Wi-Fi network, or direct peer-to-peer Wi-Fi (`includePeerToPeer`). Wi-Fi must be switched on; Bluetooth is not used. |
| Framing | One WebSocket **binary** message per envelope. |
| Security | TLS-PSK (`TLS_PSK_WITH_AES_128_GCM_SHA256`), identity `buzzlight`, key = SHA-256 of a constant. Changing either breaks compatibility. |
| Delivery | TCP, reliable and ordered per player; `TCP_NODELAY` on. |

Players read `v` to grey out incompatible hosts before connecting; a host that receives a frame
with another version closes that connection.

The legacy Multipeer transport (DEBUG A/B only, ADR 0001 → 0007) used MC discovery info with the
same `session`/`v` keys under the service type `buzzlight-mc`, plus a `v=<version>` invitation context.

## Messages

| Case | Direction | Payload | When |
|---|---|---|---|
| `hello` | P→H | `playerID`, `name` | Immediately after the transport reports the host connected. Re-sent on reconnect; same `playerID` ⇒ rename/re-map, not a duplicate. |
| `welcome` | H→P | `snapshot: SessionSnapshot` | Reply to `hello`. Full state so late joiners render correctly. |
| `roster` | H→* | `players: [Player]` | Any roster change (join, leave, rename, kick). Host is included with `isHost = true`. |
| `armed` | H→* | `round: RoundID` | Host opened the round. |
| `buzz` | P→H | `round: RoundID` | Player pressed the buzzer. Sent even when the player believes the round is idle (early press). |
| `result` | H→* | `round`, `ranking: [BuzzEntry]` | After every accepted buzz; `ranking` is complete so far. |
| `lockout` | H→P | `round: RoundID` | That player buzzed too early and is out for this round. |
| `reset` | H→* | `round: RoundID` | New idle round with this ID; clients clear ranking and lockouts. |
| `scores` | H→* | `[PlayerID: Int]` | Host awarded points. |
| `kick` | H→P | — | Player removed. Followed by `roster` to everyone else. |
| `end` | H→* | — | Session over. |
| `ping` / `pong` | both | `id: UInt32` | RTT estimation (Stage 4). Receivers answer `ping` with `pong` carrying the same id. |

### Types

```
PlayerID        { rawValue: String }            // UUID string, stable per install
RoundID         { rawValue: Int }               // 1, 2, 3… per session
Player          { id, name, isHost }
BuzzEntry       { playerID, position (1-based), deltaMilliseconds (0 for winner) }
RoundState      { id, phase: idle|armed|resolved, ranking: [BuzzEntry], lockedOut: [PlayerID] }
SessionSnapshot { players: [Player], round: RoundState, scores: [PlayerID: Int], names: [PlayerID: String]? }
```

## Sequence (happy path)

```
Player                         Host
  │── hello(id, name) ─────────▶│  adds player
  │◀─ welcome(snapshot) ────────│
  │◀─ roster ───────────────────│  (to everyone)
  │                             │  host taps Arm
  │◀─ armed(r1) ────────────────│
  │── buzz(r1) ────────────────▶│  arrival order ranks it
  │◀─ result(r1, [...]) ────────│  (to everyone, repeated per buzz)
  │                             │  host taps Next round
  │◀─ reset(r2) ────────────────│
  │◀─ armed(r2) ────────────────│
```

## Versioning rules

1. Adding a new enum case is a **breaking change** for older receivers (unknown key fails to
   decode) ⇒ bump `currentVersion`.
2. Adding an optional field to an existing payload is backward compatible; do not bump.
3. The host and all players must run the same `version`; there is no negotiation in v1.
4. Record every version bump in this file with the date and the reason.

| Version | Date | Change |
|---|---|---|
| 1 | 2026-10-25 | Initial protocol (Stage 1). |
| 1 | 2026-10-25 | Stage 3: optional `SessionSnapshot.names` (everyone ever in the session, so late joiners can label departed scorers). Optional field ⇒ no bump (rule 2). |
