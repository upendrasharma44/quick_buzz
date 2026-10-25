# Wire protocol

Source of truth: `Packages/BuzzCore/Sources/BuzzCore/Protocol.swift`. Round-trip tests:
`Tests/BuzzCoreTests/ProtocolTests.swift`.

## Envelope

Every frame is one JSON object produced by `GameMessageCodec`:

```json
{ "version": 1, "message": { "<case>": { ...payload } } }
```

- `version` — `Envelope.currentVersion`, currently **1**. A receiver that gets a different version
  throws `ProtocolError.unsupportedVersion` and should surface "update the app" to the user.
- `message` — Swift `Codable` synthesized enum encoding: the case name is the single key; cases
  without payload encode as `{ "kick": {} }`.
- Keys are sorted for stable output. Messages are small (< 2 KB); Multipeer sends them as
  `.reliable` data frames.

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
SessionSnapshot { players: [Player], round: RoundState, scores: [PlayerID: Int] }
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
